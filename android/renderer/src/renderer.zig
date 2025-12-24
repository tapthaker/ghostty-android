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
const DynamicFontSystem = @import("dynamic_font_system.zig").DynamicFontSystem;
const font_metrics = @import("font_metrics.zig");
const TerminalManager = @import("terminal_manager.zig");
const screen_extractor = @import("screen_extractor.zig");

const log = std.log.scoped(.renderer);

const Self = @This();

/// Allocator for renderer resources
allocator: std.mem.Allocator,

/// Dynamic font system with full UTF-8 support
font_system: DynamicFontSystem,

/// Terminal manager for VT processing
terminal_manager: TerminalManager,

/// Surface dimensions in pixels
width: u32 = 0,
height: u32 = 0,

/// Screen DPI (dots per inch) from Android
dpi: u16 = 160, // Default to mdpi baseline

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
pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, dpi: u16) !Self {
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

    // Initialize dynamic font system with full UTF-8 support
    // initDefault uses 10pt as the default size (see font_metrics.zig)
    var font_system = try DynamicFontSystem.initDefault(allocator, dpi);
    errdefer font_system.deinit();

    const default_size = font_metrics.FontSize.default(dpi);
    log.info("Font system initialized with {d:.1}pt font at {d} DPI", .{ default_size.points, dpi });

    // Get the actual cell size from the font system
    const actual_cell_size = font_system.getCellSize();
    const cell_width = @as(u32, @intFromFloat(actual_cell_size[0]));
    const cell_height = @as(u32, @intFromFloat(actual_cell_size[1]));

    const font_size_px = default_size.toPixels();
    log.info("Font metrics: {d:.1}pt = {d:.1}px at {d} DPI", .{ default_size.points, font_size_px, dpi });
    log.info("Cell dimensions: {d}x{d} pixels", .{ cell_width, cell_height });

    // Calculate viewport padding needed to prevent glyph clipping
    // Glyphs can extend past their cell boundaries due to font bearings
    const padding = font_system.getViewportPadding();
    log.info("Viewport padding: right={d}px, bottom={d}px", .{ padding.right, padding.bottom });

    // Calculate grid dimensions based on screen size and font-derived cell size
    const screen_w = if (width > 0) width else 800;
    const screen_h = if (height > 0) height else 600;

    log.info("Screen dimensions: {d}x{d} pixels", .{ screen_w, screen_h });
    log.info("Calculating grid: screen_width({d}) / cell_width({d}) = {d} cols", .{
        screen_w, cell_width, screen_w / cell_width
    });
    log.info("Calculating grid: screen_height({d}) / cell_height({d}) = {d} rows", .{
        screen_h, cell_height, screen_h / cell_height
    });

    const grid = font_metrics.GridCalculator.calculate(
        screen_w,
        screen_h,
        cell_width,
        cell_height,
        24,  // min_cols - reduced for mobile screens
        16   // min_rows - reduced for mobile screens
    );
    const initial_grid_cols = grid.cols;
    const initial_grid_rows = grid.rows;

    log.info("Final terminal grid: {d} cols × {d} rows", .{
        initial_grid_cols,
        initial_grid_rows,
    });

    // Verify the calculation
    const actual_width_used = initial_grid_cols * cell_width;
    const actual_height_used = initial_grid_rows * cell_height;
    log.info("Grid uses {d}x{d} pixels of {d}x{d} available", .{
        actual_width_used, actual_height_used, screen_w, screen_h
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

    // Get atlas dimensions from dynamic font system
    const font_atlas_dims = font_system.getAtlasDimensions();
    const atlas_width: u32 = font_atlas_dims[0];
    const atlas_height: u32 = font_atlas_dims[1];

    log.info("Atlas dimensions: {d}x{d}", .{ atlas_width, atlas_height });

    // Get the first grayscale atlas texture ID from the dynamic font system
    // The DynamicFontSystem manages its own atlases internally
    const grayscale_texture_id = font_system.getGrayscaleAtlas(0) orelse {
        log.err("No grayscale atlas available from DynamicFontSystem", .{});
        return error.NoGrayscaleAtlas;
    };

    // Create a Texture wrapper around the existing OpenGL texture
    const atlas_grayscale = Texture{
        .texture = gl.Texture{ .id = grayscale_texture_id },
        .width = atlas_width,
        .height = atlas_height,
        .format = .red,
    };
    errdefer {} // Don't deinit - DynamicFontSystem owns this texture

    // Get the first RGBA atlas texture ID from the dynamic font system
    // This is used for color emoji
    const rgba_texture_id = font_system.getRgbaAtlas(0) orelse {
        log.err("No RGBA atlas available from DynamicFontSystem", .{});
        return error.NoRgbaAtlas;
    };

    // Create a Texture wrapper around the existing OpenGL texture
    const atlas_color = Texture{
        .texture = gl.Texture{ .id = rgba_texture_id },
        .width = atlas_width,
        .height = atlas_height,
        .format = .rgba,
    };
    errdefer {} // Don't deinit - DynamicFontSystem owns this texture

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

    // Projection matrix must match screen_size exactly for text/background alignment
    // Previously included padding which caused text to scale differently from backgrounds
    // (text was scaled by screen_size/projection_size, causing ~3.4px drift per row)
    // Note: padding is still logged below for debugging but not used in projection
    const projection_width = actual_width;
    const projection_height = actual_height;

    // Set OpenGL viewport to actual screen size
    gl.viewport(
        0,
        0,
        @intFromFloat(actual_width),
        @intFromFloat(actual_height),
    );
    log.info("Viewport set to {d}x{d} (actual screen size)", .{
        @as(u32, @intFromFloat(actual_width)),
        @as(u32, @intFromFloat(actual_height))
    });

    const uniforms = shaders.Uniforms{
        .projection_matrix = shaders.createOrthoMatrix(projection_width, projection_height),
        .screen_size = .{ actual_width, actual_height },
        .cell_size = font_system.getCellSize(), // Use actual font metrics
        .grid_size_packed_2u16 = shaders.Uniforms.pack2u16(@intCast(initial_grid_cols), @intCast(initial_grid_rows)),
        .grid_padding = .{ 0.0, 0.0, 0.0, 0.0 },
        .padding_extend = .{
            .right = true,  // Extend rightmost cell colors into right padding
            .down = true,   // Extend bottommost cell colors into bottom padding
        },
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
        .font_decoration_metrics = font_system.getDecorationMetrics(), // Font-based decoration positions
        .baseline = font_system.getBaseline(), // Baseline position for glyph positioning
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
        .dpi = dpi,
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

    // Projection matrix must match screen_size exactly for text/background alignment
    // Previously included padding which caused text to scale differently from backgrounds
    const projection_width = @as(f32, @floatFromInt(width));
    const projection_height = @as(f32, @floatFromInt(height));

    self.uniforms.projection_matrix = shaders.createOrthoMatrix(
        projection_width,
        projection_height,
    );

    // Set OpenGL viewport to actual screen size
    gl.viewport(
        0,
        0,
        @intCast(width),
        @intCast(height),
    );

    // Calculate terminal grid dimensions based on screen size and cell size
    const cell_width = @as(u32, @intFromFloat(self.uniforms.cell_size[0]));
    const cell_height = @as(u32, @intFromFloat(self.uniforms.cell_size[1]));

    // Use GridCalculator for proper grid dimension calculation
    const grid = font_metrics.GridCalculator.calculate(
        width,
        height,
        cell_width,
        cell_height,
        24,  // min_cols - reduced for mobile screens
        16   // min_rows - reduced for mobile screens
    );
    const new_cols = grid.cols;
    const new_rows = grid.rows;

    // Only resize terminal if dimensions actually changed
    if (new_cols != self.grid_cols or new_rows != self.grid_rows) {
        log.info("Resizing terminal from {d}x{d} to {d}x{d}", .{
            self.grid_cols, self.grid_rows, new_cols, new_rows
        });

        log.info("Terminal will wrap at column {d} (visible width)", .{new_cols});

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
    // Convert pixels to points using the stored DPI
    const font_size_pts = (@as(f32, @floatFromInt(new_font_size)) * 72.0) / @as(f32, @floatFromInt(self.dpi));
    // Create a new font size from the point size
    const font_size = font_metrics.FontSize{
        .points = @floatCast(font_size_pts),
        .dpi = self.dpi,
    };
    self.font_system = try DynamicFontSystem.init(self.allocator, font_size);
    errdefer self.font_system.deinit();

    log.info("New font system initialized with size {d:.1}pt ({d}px) at {d} DPI", .{ font_size_pts, new_font_size, self.dpi });

    // 3. Get new atlas dimensions
    const font_atlas_dims = self.font_system.getAtlasDimensions();
    const atlas_width: u32 = font_atlas_dims[0];
    const atlas_height: u32 = font_atlas_dims[1];

    log.info("New atlas dimensions: {d}x{d}", .{ atlas_width, atlas_height });

    // 4. Update atlas references
    // The DynamicFontSystem manages its own atlases, so we just need to update our references
    const grayscale_texture_id = self.font_system.getGrayscaleAtlas(0) orelse {
        log.err("No grayscale atlas available from DynamicFontSystem", .{});
        return error.NoGrayscaleAtlas;
    };

    const rgba_texture_id = self.font_system.getRgbaAtlas(0) orelse {
        log.err("No RGBA atlas available from DynamicFontSystem", .{});
        return error.NoRgbaAtlas;
    };

    // Update the texture wrappers with the new IDs
    // Don't deinit - DynamicFontSystem owns the textures
    self.atlas_grayscale = Texture{
        .texture = gl.Texture{ .id = grayscale_texture_id },
        .width = atlas_width,
        .height = atlas_height,
        .format = .red,
    };

    self.atlas_color = Texture{
        .texture = gl.Texture{ .id = rgba_texture_id },
        .width = atlas_width,
        .height = atlas_height,
        .format = .rgba,
    };

    log.info("Atlas references updated", .{});

    // 6. Update atlas dimensions UBO
    const atlas_dims = shaders.AtlasDimensions{
        .grayscale_size = .{ @floatFromInt(atlas_width), @floatFromInt(atlas_height) },
        .color_size = .{ @floatFromInt(atlas_width), @floatFromInt(atlas_height) },
    };
    try self.atlas_dims_buffer.sync(&[_]shaders.AtlasDimensions{atlas_dims});

    log.info("Atlas dimensions buffer updated", .{});

    // 7. Update cell size and decoration metrics in uniforms
    const cell_size = self.font_system.getCellSize();
    self.uniforms.cell_size = cell_size;
    self.uniforms.font_decoration_metrics = self.font_system.getDecorationMetrics(); // Update decoration metrics
    self.uniforms.baseline = self.font_system.getBaseline(); // Update baseline for glyph positioning

    log.info("Cell size updated to: {}x{}", .{ cell_size[0], cell_size[1] });

    // 8. Recalculate grid dimensions based on new cell size
    const new_cell_width = @as(u32, @intFromFloat(cell_size[0]));
    const new_cell_height = @as(u32, @intFromFloat(cell_size[1]));

    const grid = font_metrics.GridCalculator.calculate(
        self.width,
        self.height,
        new_cell_width,
        new_cell_height,
        80,  // min_cols
        24   // min_rows
    );

    // Only resize terminal if dimensions actually changed
    if (grid.cols != self.grid_cols or grid.rows != self.grid_rows) {
        log.info("Font size change: resizing terminal {d}x{d} → {d}x{d}", .{
            self.grid_cols, self.grid_rows, grid.cols, grid.rows
        });

        // Before resize, log current terminal state
        const old_size = self.terminal_manager.getSize();
        log.info("Terminal size before resize: {d}x{d}", .{ old_size.cols, old_size.rows });

        // Sample some terminal content before resize
        const terminal = self.terminal_manager.getTerminal();
        const screen = terminal.screens.get(.primary).?;
        log.info("Before resize: screen has {} total rows, cursor at row {}", .{
            screen.pages.total_rows, screen.cursor.y
        });

        try self.terminal_manager.resize(grid.cols, grid.rows);

        // After resize, verify the new size and content
        const new_size = self.terminal_manager.getSize();
        log.info("Terminal size after resize: {d}x{d}", .{ new_size.cols, new_size.rows });

        // Check if content changed after resize
        const screen_after = terminal.screens.get(.primary).?;
        log.info("After resize: screen has {} total rows, cursor at row {}", .{
            screen_after.pages.total_rows, screen_after.cursor.y
        });

        self.grid_cols = grid.cols;
        self.grid_rows = grid.rows;

        // Update grid size in uniforms
        self.uniforms.grid_size_packed_2u16 = shaders.Uniforms.pack2u16(grid.cols, grid.rows);
    }

    // Sync all uniform changes
    try self.uniforms_buffer.sync(&[_]shaders.Uniforms{self.uniforms});

    // 9. Re-sync terminal content after resize to trigger proper reflow
    // This is crucial - the terminal has been resized and we need to
    // extract the reflowed content from ghostty-vt
    // Don't generate test glyphs here - syncFromTerminal will populate
    // the glyphs buffer with actual terminal content
    log.info("Calling syncFromTerminal to extract reflowed content after resize", .{});
    try self.syncFromTerminal();

    log.info("Font size update completed successfully - font_size={d:.1}pt, grid={}x{}", .{ self.font_system.collection.font_size.points, self.grid_cols, self.grid_rows });
}

/// Update renderer buffers from terminal state
pub fn syncFromTerminal(self: *Self) !void {
    log.info("syncFromTerminal: Starting sync - grid_cols={} grid_rows={}", .{ self.grid_cols, self.grid_rows });

    // Extract cell data from terminal
    const cells = try screen_extractor.extractCells(
        self.allocator,
        self.terminal_manager.getTerminal(),
    );
    defer screen_extractor.freeCells(self.allocator, cells);

    log.info("syncFromTerminal: Extracted {} cells from terminal (expected {})", .{ cells.len, self.grid_cols * self.grid_rows });

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
    var wide_char_count: usize = 0;
    for (cells) |cell| {
        const idx: usize = @as(usize, cell.row) * @as(usize, self.grid_cols) + @as(usize, cell.col);

        // Pack background color (RGBA8)
        cell_bg_colors[idx] = shaders.Uniforms.pack4u8(
            cell.bg_color[0],
            cell.bg_color[1],
            cell.bg_color[2],
            cell.bg_color[3],
        );

        // Skip wide character continuation cells
        if (cell.is_wide_continuation) {
            continue;
        }

        // Skip null characters (empty/uninitialized cells)
        if (cell.codepoint == 0) {
            skipped_count += 1;
            continue;
        }

        // Track wide characters
        if (cell.width == 2) {
            wide_char_count += 1;
        }

        // Only add renderable glyphs (skip spaces with default colors)
        if (cell.codepoint != ' ' or cell.fg_color[0] != 255 or cell.fg_color[1] != 255 or cell.fg_color[2] != 255) {
            // Track non-ASCII characters
            if (cell.codepoint > 127) {
                non_ascii_count += 1;
            }

            // Convert CellData attributes to CellText attributes
            const attributes = shaders.CellText.Attributes{
                .bold = cell.bold,
                .italic = cell.italic,
                .dim = cell.dim,
                .strikethrough = cell.strikethrough,
                .underline = @enumFromInt(@intFromEnum(cell.underline)),
                .inverse = cell.inverse,
            };

            // For inverse video, render a background rectangle first
            if (cell.inverse) {
                // Render a full block character as background with swapped colors
                const block_char: u32 = 0x2588; // █ Full block character

                // Create attributes without inverse (we're manually swapping colors)
                const bg_attributes = shaders.CellText.Attributes{
                    .bold = false,
                    .italic = false,
                    .dim = false,
                    .strikethrough = false,
                    .underline = .none,
                    .inverse = false,
                };

                // Render the background block with original foreground color (which becomes background in inverse)
                try text_glyphs.append(self.allocator, (&self.font_system).makeCellText(
                    @intCast(block_char),
                    cell.col,
                    cell.row,
                    cell.fg_color, // Use fg color for the background block
                    bg_attributes,
                    1, // Block char is always single-width
                ));
            }

            try text_glyphs.append(self.allocator, (&self.font_system).makeCellText(
                cell.codepoint,
                cell.col,
                cell.row,
                cell.fg_color,
                attributes,
                cell.width, // Pass character width (1 for normal, 2 for wide chars)
            ));

            // Strikethrough is now rendered in the fragment shader as a graphical overlay
            // No need to add separate strikethrough characters anymore

            // Underline is now rendered in the fragment shader as a graphical overlay
            // No need to add separate underline characters anymore
        } else {
            skipped_count += 1;
        }
    }

    log.info("Cell processing: {} total cells, {} glyphs added, {} spaces skipped, {} non-ASCII, {} wide chars", .{
        cells.len,
        text_glyphs.items.len,
        skipped_count,
        non_ascii_count,
        wide_char_count,
    });

    // Log sample of first row content for debugging
    if (cells.len > 0) {
        var sample_text: [80]u8 = undefined;
        var idx: usize = 0;
        for (cells[0..@min(self.grid_cols, cells.len)]) |cell| {
            if (idx < 79 and cell.codepoint >= 32 and cell.codepoint < 127) {
                sample_text[idx] = @truncate(cell.codepoint);
                idx += 1;
            }
        }
        if (idx > 0) {
            log.info("First row sample: {s}", .{sample_text[0..idx]});
        }
    }

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

// ============================================================================
// Scrolling API
// ============================================================================

/// Get the number of scrollback rows available
pub fn getScrollbackRows(self: *Self) usize {
    return self.terminal_manager.getScrollbackRows();
}

/// Get the font line spacing (cell height) for scroll calculations
pub fn getFontLineSpacing(self: *Self) f32 {
    return self.uniforms.cell_size[1];
}

/// Scroll the viewport by a delta number of rows
/// Positive delta scrolls down (towards newer content/active area)
/// Negative delta scrolls up (towards older content/scrollback)
pub fn scrollDelta(self: *Self, delta: i32) void {
    self.terminal_manager.scrollDelta(delta);
}

/// Check if viewport is at the bottom (following active area)
pub fn isViewportAtBottom(self: *Self) bool {
    return self.terminal_manager.isViewportAtBottom();
}

/// Get the current scroll offset from the top (0 = at top of scrollback)
pub fn getViewportOffset(self: *Self) usize {
    return self.terminal_manager.getViewportOffset();
}

/// Scroll viewport to the bottom (active area)
pub fn scrollToBottom(self: *Self) void {
    self.terminal_manager.scrollToBottom();
}
