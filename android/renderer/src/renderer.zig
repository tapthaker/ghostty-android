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

const log = std.log.scoped(.renderer);

const Self = @This();

/// Allocator for renderer resources
allocator: std.mem.Allocator,

/// Surface dimensions in pixels
width: u32 = 0,
height: u32 = 0,

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

/// Initialize the renderer
pub fn init(allocator: std.mem.Allocator) !Self {
    log.info("Initializing renderer", .{});

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

    // Create cell backgrounds SSBO
    // For testing: 80x24 grid = 1920 cells
    const grid_cols: u32 = 80;
    const grid_rows: u32 = 24;
    const num_cells = grid_cols * grid_rows;

    var cells_bg_buffer = try Buffer(u32).init(.{
        .target = .shader_storage,
        .usage = .dynamic_draw,
    }, num_cells);
    errdefer cells_bg_buffer.deinit();

    // Initialize test data (checkerboard pattern)
    var cell_colors = try allocator.alloc(u32, num_cells);
    defer allocator.free(cell_colors);

    for (0..grid_rows) |row| {
        for (0..grid_cols) |col| {
            const idx = row * grid_cols + col;

            // Create checkerboard: alternate between red and green
            const is_dark = (row + col) % 2 == 0;
            if (is_dark) {
                // Dark red (128, 0, 0, 255)
                cell_colors[idx] = shaders.Uniforms.pack4u8(128, 0, 0, 255);
            } else {
                // Dark green (0, 128, 0, 255)
                cell_colors[idx] = shaders.Uniforms.pack4u8(0, 128, 0, 255);
            }
        }
    }

    // Upload test data to GPU
    try cells_bg_buffer.sync(cell_colors);

    // Bind SSBO to binding point 1 (matches shader layout)
    cells_bg_buffer.bindBase(1);

    // Create font atlas textures
    // For testing: 512x512 textures (will be updated with real font data later)
    const atlas_size: usize = 512;

    // Grayscale atlas (R8 format for regular text)
    const atlas_grayscale = try Texture.init(.{
        .format = .red,
        .internal_format = .r8,
        .min_filter = .nearest,
        .mag_filter = .nearest,
    }, atlas_size, atlas_size, null);
    errdefer atlas_grayscale.deinit();

    // Color atlas (RGBA8 format for color emoji)
    const atlas_color = try Texture.init(.{
        .format = .rgba,
        .internal_format = .rgba8,
        .min_filter = .nearest,
        .mag_filter = .nearest,
    }, atlas_size, atlas_size, null);
    errdefer atlas_color.deinit();

    // Create atlas dimensions UBO
    var atlas_dims_buffer = try Buffer(shaders.AtlasDimensions).init(.{
        .target = .uniform,
        .usage = .static_draw,
    }, 1);
    errdefer atlas_dims_buffer.deinit();

    const atlas_dims = shaders.AtlasDimensions{
        .grayscale_size = .{ @floatFromInt(atlas_size), @floatFromInt(atlas_size) },
        .color_size = .{ @floatFromInt(atlas_size), @floatFromInt(atlas_size) },
    };
    try atlas_dims_buffer.sync(&[_]shaders.AtlasDimensions{atlas_dims});

    // Bind atlas dimensions to binding point 2
    atlas_dims_buffer.bindBase(2);

    // Load and compile cell_text shaders
    const cell_text_vertex_src = shader_module.loadShaderCode("shaders/glsl/cell_text.v.glsl");
    const cell_text_fragment_src = shader_module.loadShaderCode("shaders/glsl/cell_text.f.glsl");

    // Create cell text pipeline with auto-configured vertex attributes for instanced rendering
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
    if (atlas_grayscale_loc >= 0) {
        gl.uniform1i(atlas_grayscale_loc, 0); // Texture unit 0
    }
    const atlas_color_loc = cell_text_pipeline.program.getUniformLocation("atlas_color");
    if (atlas_color_loc >= 0) {
        gl.uniform1i(atlas_color_loc, 1); // Texture unit 1
    }

    // Create glyphs instance buffer
    // For testing: allocate space for 1920 glyphs (80x24 full screen)
    const max_glyphs = grid_cols * grid_rows;
    var glyphs_buffer = try Buffer(shaders.CellText).init(.{
        .target = .array,
        .usage = .dynamic_draw,
    }, max_glyphs);
    errdefer glyphs_buffer.deinit();

    // Initialize default uniforms
    const uniforms = shaders.Uniforms{
        .projection_matrix = shaders.createOrthoMatrix(800.0, 600.0), // Will be updated on resize
        .screen_size = .{ 800.0, 600.0 },
        .cell_size = .{ 12.0, 24.0 }, // Default cell size
        .grid_size_packed_2u16 = shaders.Uniforms.pack2u16(80, 24), // 80x24 default
        .grid_padding = .{ 0.0, 0.0, 0.0, 0.0 },
        .padding_extend = .{},
        .min_contrast = 1.0,
        .cursor_pos_packed_2u16 = shaders.Uniforms.pack2u16(0, 0),
        .cursor_color_packed_4u8 = shaders.Uniforms.pack4u8(255, 255, 255, 255), // White
        .bg_color_packed_4u8 = shaders.Uniforms.pack4u8(40, 20, 60, 255), // Purple (for testing)
        .bools = .{
            .cursor_wide = false,
            .use_display_p3 = false,
            .use_linear_blending = false,
            .use_linear_correction = false,
        },
    };

    log.info("Renderer initialized successfully", .{});

    return .{
        .allocator = allocator,
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

    // Upload updated uniforms to GPU
    try self.syncUniforms();
}

/// Sync uniforms buffer with current state
fn syncUniforms(self: *Self) !void {
    try self.uniforms_buffer.sync(&[_]shaders.Uniforms{self.uniforms});
}

/// Render a frame
pub fn render(self: *Self) !void {
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

    // Render cell text (blended over cell backgrounds)
    // For now, we'll render 0 glyphs (will add test glyphs later)
    self.cell_text_pipeline.use();

    // Bind font atlas textures to their respective texture units
    self.atlas_grayscale.bindToUnit(0); // Texture unit 0
    self.atlas_color.bindToUnit(1);     // Texture unit 1

    // Draw glyphs using instanced rendering (4 vertices per glyph instance)
    const num_glyphs: u32 = 0; // TODO: Will be set to actual glyph count
    if (num_glyphs > 0) {
        gl.drawArraysInstanced(gl.GL_TRIANGLE_STRIP, 0, 4, @intCast(num_glyphs));
    }

    // Check for errors
    try gl.checkError();
}

/// Update background color
pub fn setBackgroundColor(self: *Self, r: u8, g: u8, b: u8, a: u8) void {
    self.uniforms.bg_color_packed_4u8 = shaders.Uniforms.pack4u8(r, g, b, a);
}
