///! Texture management for OpenGL ES 3.1
///!
///! Wrapper for handling textures with proper lifetime management.

const std = @import("std");
const gl = @import("gl_es.zig");

const Self = @This();

/// Options for initializing a texture.
pub const Options = struct {
    format: gl.Texture.Format,
    internal_format: gl.Texture.InternalFormat,
    min_filter: gl.Texture.Filter = .nearest,
    mag_filter: gl.Texture.Filter = .nearest,
    wrap_s: gl.Texture.Wrap = .clamp_to_edge,
    wrap_t: gl.Texture.Wrap = .clamp_to_edge,
};

/// The GL texture object
texture: gl.Texture,

/// The width of this texture in pixels
width: usize,

/// The height of this texture in pixels
height: usize,

/// Format for this texture
format: gl.Texture.Format,

pub const Error = error{
    /// An OpenGL API call failed
    OpenGLFailed,
};

/// Initialize a texture
pub fn init(
    opts: Options,
    width: usize,
    height: usize,
    data: ?[]const u8,
) Error!Self {
    const tex = gl.Texture.create() catch return error.OpenGLFailed;
    errdefer tex.delete();

    // Bind and configure texture
    tex.bind(.texture_2d);
    defer gl.Texture.unbind(.texture_2d);

    gl.Texture.parameter(
        .texture_2d,
        .wrap_s,
        @intCast(@intFromEnum(opts.wrap_s)),
    );
    gl.Texture.parameter(
        .texture_2d,
        .wrap_t,
        @intCast(@intFromEnum(opts.wrap_t)),
    );
    gl.Texture.parameter(
        .texture_2d,
        .min_filter,
        @intCast(@intFromEnum(opts.min_filter)),
    );
    gl.Texture.parameter(
        .texture_2d,
        .mag_filter,
        @intCast(@intFromEnum(opts.mag_filter)),
    );

    // Upload texture data
    gl.Texture.image2D(
        .texture_2d,
        0,
        opts.internal_format,
        @intCast(width),
        @intCast(height),
        opts.format,
        if (data) |d| @ptrCast(d.ptr) else null,
    );

    return .{
        .texture = tex,
        .width = width,
        .height = height,
        .format = opts.format,
    };
}

pub fn deinit(self: Self) void {
    self.texture.delete();
}

/// Replace a region of the texture with the provided data.
///
/// Does NOT check the dimensions of the data to ensure correctness.
pub fn replaceRegion(
    self: Self,
    x: usize,
    y: usize,
    width: usize,
    height: usize,
    data: []const u8,
) Error!void {
    self.texture.bind(.texture_2d);
    defer gl.Texture.unbind(.texture_2d);

    gl.Texture.subImage2D(
        .texture_2d,
        0,
        @intCast(x),
        @intCast(y),
        @intCast(width),
        @intCast(height),
        self.format,
        data.ptr,
    );

    gl.checkError() catch return error.OpenGLFailed;
}

/// Bind this texture to a specific texture unit
pub fn bindToUnit(self: Self, unit: u32) void {
    gl.Texture.active(unit);
    self.texture.bind(.texture_2d);
}
