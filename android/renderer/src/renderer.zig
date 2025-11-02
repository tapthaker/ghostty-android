///! Main renderer module for Ghostty Android
///!
///! This manages all rendering pipelines and state for the terminal renderer.

const std = @import("std");
const gl = @import("gl_es.zig");
const Pipeline = @import("pipeline.zig");
const Buffer = @import("buffer.zig").Buffer;
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

    // Create uniforms buffer
    var uniforms_buffer = try Buffer(shaders.Uniforms).init(.{
        .target = .uniform,
        .usage = .dynamic_draw,
    }, 1);
    errdefer uniforms_buffer.deinit();

    // Bind uniforms buffer to binding point 1 (matches shader layout)
    uniforms_buffer.bindBase(1);

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
    };
}

pub fn deinit(self: *Self) void {
    log.info("Destroying renderer", .{});
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

    // Check for errors
    try gl.checkError();
}

/// Update background color
pub fn setBackgroundColor(self: *Self, r: u8, g: u8, b: u8, a: u8) void {
    self.uniforms.bg_color_packed_4u8 = shaders.Uniforms.pack4u8(r, g, b, a);
}
