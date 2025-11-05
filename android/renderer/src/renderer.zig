///! Main renderer module for Ghostty Android
///!
///! This manages all rendering pipelines and state for the terminal renderer.

const std = @import("std");
const gl = @import("gl_es.zig");
const Pipeline = @import("pipeline.zig");
const Buffer = @import("buffer.zig").Buffer;
const Texture = @import("texture.zig");
const shaders = @import("shaders.zig");
const shader_module = @import("shader.zig");
const FontSystem = @import("font_system.zig").FontSystem;
const TerminalManager = @import("terminal_manager.zig");
const screen_extractor = @import("screen_extractor.zig");

const log = std.log.scoped(.renderer);

const Self = @This();

/// Allocator for renderer resources
allocator: std.mem.Allocator,

/// Font system for text rendering
font_system: FontSystem,

/// Terminal manager for VT processing
terminal_manager: TerminalManager,

/// Surface dimensions in pixels
width: u32 = 0,
height: u32 = 0,

/// Grid dimensions (terminal columns x rows)
grid_cols: u16 = 80,
grid_rows: u16 = 24,

/// Global uniforms buffer (UBO at binding point 1)
uniforms_buffer: Buffer(shaders.Uniforms),

/// Current uniforms state
uniforms: shaders.Uniforms,

/// Background color rendering pipeline
bg_color_pipeline: Pipeline,

/// Cell backgrounds SSBO (binding point 1) - holds per-cell background colors
cells_bg_buffer: Buffer(u32),

/// Cell backgrounds rendering pipeline
cell_bg_pipeline: Pipeline,

/// Grayscale font atlas (R8 texture) - for regular text glyphs
atlas_grayscale: Texture,

/// Color font atlas (RGBA8 texture) - for color emoji glyphs
atlas_color: Texture,

/// Atlas dimensions UBO (binding point 2)
atlas_dims_buffer: Buffer(shaders.AtlasDimensions),

/// Glyph instances buffer for cell_text pipeline
glyphs_buffer: Buffer(shaders.CellText),

/// Cell text rendering pipeline
cell_text_pipeline: Pipeline,

/// Number of glyphs to render (for testing)
num_test_glyphs: u32 = 0,

/// Initialize the renderer with optional initial dimensions
pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !Self {
    log.info("Initializing renderer with dimensions: {d}x{d}", .{ width, height });

    // Load and compile bg_color shaders
    const bg_color_vertex_src = shader_module.loadShaderCode("shaders/glsl/full_screen.v.glsl");
    const bg_color_fragment_src = shader_module.loadShaderCode("shaders/glsl/bg_color.f.glsl");

    // Create background color pipeline (no vertex attributes - full-screen triangle)
    const bg_color_pipeline = try Pipeline.init(null, .{
        .vertex_src = bg_color_vertex_src,
        .fragment_src = bg_color_fragment_src,
        .blending_enabled = false, // First pass, no blending needed
    });
    errdefer bg_color_pipeline.deinit();

    // Load and compile cell_bg shaders
    const cell_bg_vertex_src = shader_module.loadShaderCode("shaders/glsl/full_screen.v.glsl");
    const cell_bg_fragment_src = shader_module.loadShaderCode("shaders/glsl/cell_bg.f.glsl");

    // Create cell backgrounds pipeline (also uses full-screen triangle)
    const cell_bg_pipeline = try Pipeline.init(null, .{
        .vertex_src = cell_bg_vertex_src,
        .fragment_src = cell_bg_fragment_src,
        .blending_enabled = true, // Blend over bg_color
    });
    errdefer cell_bg_pipeline.deinit();

    // Create uniforms buffer
    var uniforms_buffer = try Buffer(shaders.Uniforms).init(.{
        .target = .uniform,
        .usage = .dynamic_draw,
    }, 1);
    errdefer uniforms_buffer.deinit();

    // Bind uniforms buffer to binding point 0 (matches shader layout)
    // Note: We use binding 0 for UBO since binding 1 is used for SSBO
    uniforms_buffer.bindBase(0);

    // Initialize font system first to get cell dimensions
    var font_system = try FontSystem.init(allocator, 48);
    errdefer font_system.deinit();

    log.info("Font system initialized", .{});

    // Calculate initial terminal grid dimensions based on screen size
    // Use provided dimensions if non-zero, otherwise default to 80x24
    const cell_size = font_system.getCellSize();
    const cell_width = @as(u32, @intFromFloat(cell_size[0]));
    const cell_height = @as(u32, @intFromFloat(cell_size[1]));

    const initial_grid_cols: u32 = if (width > 0 and cell_width > 0)
        @min(width / cell_width, 512)
    else
        80;
    const initial_grid_rows: u32 = if (height > 0 and cell_height > 0)
        @min(height / cell_height, 512)
    else
        24;

    log.info("Calculated terminal grid: {d}x{d} (cell size: {d}x{d})", .{
        initial_grid_cols,
        initial_grid_rows,
        cell_width,
        cell_height,
    });

    // Create cell backgrounds SSBO
    // Allocate buffers with maximum capacity to handle resizing (512x512 = 262k cells)
    const max_cells: u32 = 512 * 512;

    var cells_bg_buffer = try Buffer(u32).init(.{
        .target = .shader_storage,
        .usage = .dynamic_draw,
    }, max_cells);
    errdefer cells_bg_buffer.deinit();

    // Initialize with cleared data (no checkerboard pattern needed)
    const cell_colors = try allocator.alloc(u32, max_cells);
    defer allocator.free(cell_colors);

    // Clear all cells to transparent
    @memset(cell_colors, 0);

    // Upload cleared data to GPU
    try cells_bg_buffer.sync(cell_colors);

    // Bind SSBO to binding point 1 (matches shader layout)
    cells_bg_buffer.bindBase(1);

    // Initialize terminal manager with calculated dimensions
    var terminal_manager = try TerminalManager.init(allocator, @intCast(initial_grid_cols), @intCast(initial_grid_rows));
    errdefer terminal_manager.deinit();

    log.info("Terminal manager initialized ({d}x{d})", .{ initial_grid_cols, initial_grid_rows });

    // Get dynamic atlas dimensions based on font size
    const font_atlas_dims = font_system.getAtlasDimensions();
    const atlas_width: u32 = font_atlas_dims[0];
    const atlas_height: u32 = font_atlas_dims[1];

    log.info("Atlas dimensions: {d}x{d}", .{ atlas_width, atlas_height });

    // Populate grayscale atlas with actual font glyphs
    const grayscale_data = try font_system.populateAtlas(atlas_width, atlas_height);
    defer allocator.free(grayscale_data);

    log.info("Font atlas populated with glyphs", .{});

    const atlas_grayscale = try Texture.init(.{
        .format = .red,
        .internal_format = .r8,
        .min_filter = .nearest,
        .mag_filter = .nearest,
    }, atlas_width, atlas_height, grayscale_data);
    errdefer atlas_grayscale.deinit();

    // Color atlas (RGBA8 format for color emoji)
    // Allocate with zero-filled data to ensure proper storage allocation on Mali
    const color_data = try allocator.alloc(u8, atlas_width * atlas_height * 4); // RGBA = 4 bytes per pixel
    defer allocator.free(color_data);
    @memset(color_data, 0);

    const atlas_color = try Texture.init(.{
        .format = .rgba,
        .internal_format = .rgba8,
        .min_filter = .nearest,
        .mag_filter = .nearest,
    }, atlas_width, atlas_height, color_data);
    errdefer atlas_color.deinit();

    // Create atlas dimensions UBO
    var atlas_dims_buffer = try Buffer(shaders.AtlasDimensions).init(.{
        .target = .uniform,
        .usage = .static_draw,
    }, 1);
    errdefer atlas_dims_buffer.deinit();

    const atlas_dims = shaders.AtlasDimensions{
        .grayscale_size = .{ @floatFromInt(atlas_width), @floatFromInt(atlas_height) },
        .color_size = .{ @floatFromInt(atlas_width), @floatFromInt(atlas_height) },
    };
    try atlas_dims_buffer.sync(&[_]shaders.AtlasDimensions{atlas_dims});

    // Bind atlas dimensions to binding point 2
    atlas_dims_buffer.bindBase(2);

    // Load and compile cell_text shaders
    const cell_text_vertex_src = shader_module.loadShaderCode("shaders/glsl/cell_text.v.glsl");
    const cell_text_fragment_src = shader_module.loadShaderCode("shaders/glsl/cell_text.f.glsl");

    // Create glyphs instance buffer FIRST (before pipeline)
    // Allocate with max capacity to handle terminal resizing
    var glyphs_buffer = try Buffer(shaders.CellText).init(.{
        .target = .array,
        .usage = .dynamic_draw,
    }, max_cells);
    errdefer glyphs_buffer.deinit();

    // Bind the buffer so it's active when VAO attributes are configured
    glyphs_buffer.buffer.bind(glyphs_buffer.opts.target);

    // NOW create the pipeline - the VAO will be configured with the buffer bound
    const cell_text_pipeline = try Pipeline.init(shaders.CellText, .{
        .vertex_src = cell_text_vertex_src,
        .fragment_src = cell_text_fragment_src,
        .blending_enabled = true, // Blend text over background
        .step_fn = .per_instance, // Each glyph instance gets its own attributes
    });
    errdefer cell_text_pipeline.deinit();

    // Set sampler uniforms (OpenGL ES 3.1 doesn't support layout(binding) for samplers)
    cell_text_pipeline.program.use();
    const atlas_grayscale_loc = cell_text_pipeline.program.getUniformLocation("atlas_grayscale");
    log.info("atlas_grayscale uniform location: {}", .{atlas_grayscale_loc});
    if (atlas_grayscale_loc >= 0) {
        gl.uniform1i(atlas_grayscale_loc, 0); // Texture unit 0
    } else {
        log.warn("atlas_grayscale uniform not found!", .{});
    }

    const atlas_color_loc = cell_text_pipeline.program.getUniformLocation("atlas_color");
    log.info("atlas_color uniform location: {}", .{atlas_color_loc});
    if (atlas_color_loc >= 0) {
        gl.uniform1i(atlas_color_loc, 1); // Texture unit 1
    } else {
        log.warn("atlas_color uniform not found!", .{});
    }

    // Note: We leave the program bound after setting uniforms
    // The uniforms are part of the program state and will persist

    // Extract terminal state and sync to GPU
    // (This will be done in a temporary renderer-like struct before full init)
    _ = 0; // Reserved for future test glyph count

    // Initialize default uniforms with actual dimensions
    const actual_width = if (width > 0) @as(f32, @floatFromInt(width)) else 800.0;
    const actual_height = if (height > 0) @as(f32, @floatFromInt(height)) else 600.0;

    const uniforms = shaders.Uniforms{
        .projection_matrix = shaders.createOrthoMatrix(actual_width, actual_height),
        .screen_size = .{ actual_width, actual_height },
        .cell_size = font_system.getCellSize(), // Use actual font metrics
        .grid_size_packed_2u16 = shaders.Uniforms.pack2u16(@intCast(initial_grid_cols), @intCast(initial_grid_rows)),
        .grid_padding = .{ 0.0, 0.0, 0.0, 0.0 },
        .padding_extend = .{},
        .min_contrast = 1.0,
        .cursor_pos_packed_2u16 = shaders.Uniforms.pack2u16(255, 255), // Off-screen to avoid color override
        .cursor_color_packed_4u8 = shaders.Uniforms.pack4u8(255, 255, 255, 255), // White
        .bg_color_packed_4u8 = shaders.Uniforms.pack4u8(40, 20, 60, 255), // Purple (for testing)
        .bools = .{
            .cursor_wide = false,
            .use_display_p3 = false,
            .use_linear_blending = false,
            .use_linear_correction = false,
        },
    };

    log.info("Cell size from font: {d}x{d}", .{ uniforms.cell_size[0], uniforms.cell_size[1] });
    log.info("Renderer initialized successfully with {d}x{d} grid ({d}x{d} screen)", .{
        initial_grid_cols,
        initial_grid_rows,
        actual_width,
        actual_height,
    });

    return .{
        .allocator = allocator,
        .font_system = font_system,
        .terminal_manager = terminal_manager,
        .width = if (width > 0) width else 0,
        .height = if (height > 0) height else 0,
        .grid_cols = @intCast(initial_grid_cols),
        .grid_rows = @intCast(initial_grid_rows),
        .uniforms_buffer = uniforms_buffer,
        .uniforms = uniforms,
        .bg_color_pipeline = bg_color_pipeline,
        .cells_bg_buffer = cells_bg_buffer,
        .cell_bg_pipeline = cell_bg_pipeline,
        .atlas_grayscale = atlas_grayscale,
        .atlas_color = atlas_color,
        .atlas_dims_buffer = atlas_dims_buffer,
        .glyphs_buffer = glyphs_buffer,
        .cell_text_pipeline = cell_text_pipeline,
        .num_test_glyphs = 0,
    };
}

pub fn deinit(self: *Self) void {
    log.info("Destroying renderer", .{});
    self.cell_text_pipeline.deinit();
    self.glyphs_buffer.deinit();
    self.atlas_dims_buffer.deinit();
    self.atlas_color.deinit();
    self.atlas_grayscale.deinit();
    self.cell_bg_pipeline.deinit();
    self.cells_bg_buffer.deinit();
    self.bg_color_pipeline.deinit();
    self.uniforms_buffer.deinit();
    self.terminal_manager.deinit();
    self.font_system.deinit();
}

/// Update surface size and recalculate projection matrix
pub fn resize(self: *Self, width: u32, height: u32) !void {
    log.info("Resizing renderer to {d}x{d}", .{ width, height });

    self.width = width;
    self.height = height;

    // Update screen size in uniforms
    self.uniforms.screen_size = .{
        @floatFromInt(width),
        @floatFromInt(height),
    };

    // Recalculate orthographic projection matrix
    self.uniforms.projection_matrix = shaders.createOrthoMatrix(
        @floatFromInt(width),
        @floatFromInt(height),
    );

    // Calculate terminal grid dimensions based on screen size and cell size
    const cell_width = @as(u32, @intFromFloat(self.uniforms.cell_size[0]));
    const cell_height = @as(u32, @intFromFloat(self.uniforms.cell_size[1]));

    const new_cols: u16 = @intCast(@min(width / cell_width, 512)); // Cap at 512 cols for safety
    const new_rows: u16 = @intCast(@min(height / cell_height, 512)); // Cap at 512 rows for safety

    // Only resize terminal if dimensions actually changed
    if (new_cols != self.grid_cols or new_rows != self.grid_rows) {
        log.info("Resizing terminal from {d}x{d} to {d}x{d}", .{
            self.grid_cols, self.grid_rows, new_cols, new_rows
        });

        try self.terminal_manager.resize(new_cols, new_rows);
        self.grid_cols = new_cols;
        self.grid_rows = new_rows;

        // Update uniforms with new grid size
        self.uniforms.grid_size_packed_2u16 = shaders.Uniforms.pack2u16(new_cols, new_rows);
    }

    log.info("Cell size: {d}x{d}, Grid: {d}x{d}", .{
        self.uniforms.cell_size[0], self.uniforms.cell_size[1],
        self.grid_cols, self.grid_rows
    });

    // Upload updated uniforms to GPU
    try self.syncUniforms();
}

/// Sync uniforms buffer with current state
fn syncUniforms(self: *Self) !void {
    try self.uniforms_buffer.sync(&[_]shaders.Uniforms{self.uniforms});
}

/// Render a frame
pub fn render(self: *Self) !void {
    // Sync renderer state from terminal (extract cells and update GPU buffers)
    try self.syncFromTerminal();

    // Clear with transparent black (will be overwritten by bg_color shader)
    gl.clearColor(0.0, 0.0, 0.0, 0.0);
    gl.clear(gl.GL_COLOR_BUFFER_BIT);

    // Ensure uniforms are up to date
    try self.syncUniforms();

    // Render background color using full-screen triangle
    self.bg_color_pipeline.use();
    gl.drawArrays(gl.GL_TRIANGLES, 0, 3); // Draw 3 vertices for full-screen triangle

    // Render cell backgrounds (blended over bg_color)
    self.cell_bg_pipeline.use();
    gl.drawArrays(gl.GL_TRIANGLES, 0, 3); // Draw 3 vertices for full-screen triangle

    // Check for errors after cell backgrounds (non-fatal for now)
    gl.checkError() catch |err| {
        log.warn("GL error after cell_bg rendering (non-fatal): {}", .{err});
    };

    // Render cell text (blended over cell backgrounds)
    // First activate the pipeline (which binds the VAO)
    self.cell_text_pipeline.use();
    gl.checkError() catch |err| {
        log.err("GL error after pipeline.use(): {}", .{err});
    };

    // Then bind the glyphs buffer to the active VAO
    log.debug("Binding glyphs buffer", .{});
    self.glyphs_buffer.buffer.bind(self.glyphs_buffer.opts.target);
    gl.checkError() catch |err| {
        log.err("GL error after buffer bind: {}", .{err});
    };

    // Bind font atlas textures to their respective texture units
    log.debug("Binding atlas textures", .{});
    self.atlas_grayscale.bindToUnit(0); // Texture unit 0
    gl.checkError() catch |err| {
        log.err("GL error after grayscale texture bind: {}", .{err});
    };

    self.atlas_color.bindToUnit(1);     // Texture unit 1
    gl.checkError() catch |err| {
        log.err("GL error after color texture bind: {}", .{err});
    };

    // Draw glyphs using instanced rendering (4 vertices per glyph instance)
    if (self.num_test_glyphs > 0) {
        log.debug("Drawing {} glyphs with instanced rendering", .{self.num_test_glyphs});
        gl.drawArraysInstanced(gl.GL_TRIANGLE_STRIP, 0, 4, @intCast(self.num_test_glyphs));
        gl.checkError() catch |err| {
            log.err("GL error after drawArraysInstanced: {}", .{err});
        };
    } else {
        log.warn("num_test_glyphs is 0, skipping text rendering", .{});
    }
}

/// Update background color
pub fn setBackgroundColor(self: *Self, r: u8, g: u8, b: u8, a: u8) void {
    self.uniforms.bg_color_packed_4u8 = shaders.Uniforms.pack4u8(r, g, b, a);
}

/// Update font size dynamically by rebuilding the font system and atlases
pub fn updateFontSize(self: *Self, new_font_size: u32) !void {
    log.info("Updating font size to {d}px", .{new_font_size});

    // 1. Deinitialize old font system
    self.font_system.deinit();

    // 2. Create new font system with new size
    self.font_system = try FontSystem.init(self.allocator, new_font_size);
    errdefer self.font_system.deinit();

    log.info("New font system initialized with size {d}px", .{new_font_size});

    // 3. Get new atlas dimensions
    const font_atlas_dims = self.font_system.getAtlasDimensions();
    const atlas_width: u32 = font_atlas_dims[0];
    const atlas_height: u32 = font_atlas_dims[1];

    log.info("New atlas dimensions: {d}x{d}", .{ atlas_width, atlas_height });

    // 4. Rebuild grayscale atlas
    const grayscale_data = try self.font_system.populateAtlas(atlas_width, atlas_height);
    defer self.allocator.free(grayscale_data);

    // Update the existing texture with new data
    self.atlas_grayscale.deinit();
    self.atlas_grayscale = try Texture.init(.{
        .format = .red,
        .internal_format = .r8,
        .min_filter = .nearest,
        .mag_filter = .nearest,
    }, atlas_width, atlas_height, grayscale_data);

    log.info("Grayscale atlas updated", .{});

    // 5. Rebuild color atlas (empty for now)
    const color_data = try self.allocator.alloc(u8, atlas_width * atlas_height * 4);
    defer self.allocator.free(color_data);
    @memset(color_data, 0);

    self.atlas_color.deinit();
    self.atlas_color = try Texture.init(.{
        .format = .rgba,
        .internal_format = .rgba8,
        .min_filter = .nearest,
        .mag_filter = .nearest,
    }, atlas_width, atlas_height, color_data);

    log.info("Color atlas updated", .{});

    // 6. Update atlas dimensions UBO
    const atlas_dims = shaders.AtlasDimensions{
        .grayscale_size = .{ @floatFromInt(atlas_width), @floatFromInt(atlas_height) },
        .color_size = .{ @floatFromInt(atlas_width), @floatFromInt(atlas_height) },
    };
    try self.atlas_dims_buffer.sync(&[_]shaders.AtlasDimensions{atlas_dims});

    log.info("Atlas dimensions buffer updated", .{});

    // 7. Update cell size in uniforms
    const cell_size = self.font_system.getCellSize();
    self.uniforms.cell_size = cell_size;
    try self.uniforms_buffer.sync(&[_]shaders.Uniforms{self.uniforms});

    log.info("Cell size updated to: {}x{}", .{ cell_size[0], cell_size[1] });

    // 8. Regenerate test glyphs with new font system
    const test_string = "Hello World!";
    var test_glyphs: [test_string.len]shaders.CellText = undefined;

    for (test_string, 0..) |char, i| {
        test_glyphs[i] = self.font_system.makeCellText(
            char,
            @intCast(i), // col
            0, // row
            .{ 255, 255, 255, 255 }, // white text
        );
    }

    self.num_test_glyphs = test_string.len;
    try self.glyphs_buffer.sync(&test_glyphs);

    log.info("Font size update completed successfully", .{});
}

/// Update renderer buffers from terminal state
pub fn syncFromTerminal(self: *Self) !void {
    log.debug("Syncing renderer from terminal state", .{});

    // Extract cell data from terminal
    const cells = try screen_extractor.extractCells(
        self.allocator,
        self.terminal_manager.getTerminal(),
    );
    defer screen_extractor.freeCells(self.allocator, cells);

    log.debug("Extracted {} cells from terminal", .{cells.len});

    // Allocate temp buffers for GPU data
    const num_cells: usize = @intCast(self.grid_cols * self.grid_rows);
    var cell_bg_colors = try self.allocator.alloc(u32, num_cells);
    defer self.allocator.free(cell_bg_colors);

    var text_glyphs = try std.ArrayList(shaders.CellText).initCapacity(self.allocator, num_cells);
    defer text_glyphs.deinit(self.allocator);

    // Clear all backgrounds to default
    @memset(cell_bg_colors, 0);

    // Process each cell
    var skipped_count: usize = 0;
    var non_ascii_count: usize = 0;
    for (cells) |cell| {
        const idx: usize = @as(usize, cell.row) * @as(usize, self.grid_cols) + @as(usize, cell.col);

        // Pack background color (RGBA8)
        cell_bg_colors[idx] = shaders.Uniforms.pack4u8(
            cell.bg_color[0],
            cell.bg_color[1],
            cell.bg_color[2],
            cell.bg_color[3],
        );

        // Only add renderable glyphs (skip spaces with default colors)
        if (cell.codepoint != ' ' or cell.fg_color[0] != 255 or cell.fg_color[1] != 255 or cell.fg_color[2] != 255) {
            // Track non-ASCII characters
            if (cell.codepoint > 127) {
                non_ascii_count += 1;
            }

            try text_glyphs.append(self.allocator, self.font_system.makeCellText(
                cell.codepoint,
                cell.col,
                cell.row,
                cell.fg_color,
            ));
        } else {
            skipped_count += 1;
        }
    }

    log.info("Cell processing: {} total cells, {} glyphs added, {} spaces skipped, {} non-ASCII", .{
        cells.len,
        text_glyphs.items.len,
        skipped_count,
        non_ascii_count,
    });

    // Upload to GPU
    try self.cells_bg_buffer.sync(cell_bg_colors);
    try self.glyphs_buffer.sync(text_glyphs.items);
    self.num_test_glyphs = @intCast(text_glyphs.items.len);

    log.info("Synced {} glyphs to GPU from terminal", .{self.num_test_glyphs});
}

/// Process VT input and sync to renderer
pub fn processTerminalInput(self: *Self, data: []const u8) !void {
    try self.terminal_manager.processInput(data);
    try self.syncFromTerminal();
}
