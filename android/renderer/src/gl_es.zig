///! OpenGL ES 3.1 wrapper providing ergonomic Zig interfaces to GLES calls
///!
///! This module wraps the raw C bindings from GLES3/gl31.h with Zig error handling
///! and type safety.

const std = @import("std");

pub const c = @cImport({
    @cInclude("GLES3/gl31.h");
});

const log = std.log.scoped(.gl_es);

pub const Error = error{
    ShaderCompileFailed,
    ProgramLinkFailed,
    InvalidOperation,
    OutOfMemory,
    InvalidValue,
    InvalidEnum,
    InvalidFramebuffer,
};

/// Check for OpenGL errors and return appropriate Zig error
pub fn checkError() Error!void {
    const err = c.glGetError();
    return switch (err) {
        c.GL_NO_ERROR => {},
        c.GL_INVALID_ENUM => blk: {
            log.err("OpenGL error: GL_INVALID_ENUM", .{});
            break :blk error.InvalidEnum;
        },
        c.GL_INVALID_VALUE => blk: {
            log.err("OpenGL error: GL_INVALID_VALUE", .{});
            break :blk error.InvalidValue;
        },
        c.GL_INVALID_OPERATION => blk: {
            log.err("OpenGL error: GL_INVALID_OPERATION", .{});
            break :blk error.InvalidOperation;
        },
        c.GL_OUT_OF_MEMORY => blk: {
            log.err("OpenGL error: GL_OUT_OF_MEMORY", .{});
            break :blk error.OutOfMemory;
        },
        c.GL_INVALID_FRAMEBUFFER_OPERATION => blk: {
            log.err("OpenGL error: GL_INVALID_FRAMEBUFFER_OPERATION", .{});
            break :blk error.InvalidFramebuffer;
        },
        else => blk: {
            log.err("Unknown OpenGL error: 0x{x}", .{err});
            break :blk error.InvalidOperation;
        },
    };
}

// ============================================================================
// Shader Management
// ============================================================================

pub const Shader = struct {
    id: c.GLuint,
    shader_type: Type,

    pub const Type = enum(c.GLenum) {
        vertex = c.GL_VERTEX_SHADER,
        fragment = c.GL_FRAGMENT_SHADER,
    };

    pub fn create(shader_type: Type) Error!Shader {
        const id = c.glCreateShader(@intFromEnum(shader_type));
        if (id == 0) {
            try checkError();
            return error.InvalidOperation;
        }
        return .{ .id = id, .shader_type = shader_type };
    }

    pub fn source(self: Shader, src: [:0]const u8) void {
        const src_ptr: ?[*]const u8 = src.ptr;
        const len: c.GLint = @intCast(src.len);
        c.glShaderSource(self.id, 1, &src_ptr, &len);
    }

    pub fn compile(self: Shader) Error!void {
        c.glCompileShader(self.id);

        var success: c.GLint = 0;
        c.glGetShaderiv(self.id, c.GL_COMPILE_STATUS, &success);

        if (success == 0) {
            var info_log: [4096]u8 = undefined;
            var log_length: c.GLsizei = 0;
            c.glGetShaderInfoLog(self.id, 4096, &log_length, &info_log);

            log.err("Shader compilation failed ({s}) - shader id: {}", .{
                @tagName(self.shader_type),
                self.id,
            });

            if (log_length > 0) {
                const log_str = info_log[0..@intCast(log_length)];
                log.err("Shader error log:\n{s}", .{log_str});
            } else {
                log.err("No shader info log available (log_length = 0)", .{});
            }

            return error.ShaderCompileFailed;
        }
    }

    pub fn delete(self: Shader) void {
        c.glDeleteShader(self.id);
    }
};

pub const Program = struct {
    id: c.GLuint,

    pub fn create() Error!Program {
        const id = c.glCreateProgram();
        if (id == 0) {
            try checkError();
            return error.InvalidOperation;
        }
        return .{ .id = id };
    }

    pub fn attachShader(self: Program, shader: Shader) void {
        c.glAttachShader(self.id, shader.id);
    }

    pub fn link(self: Program) Error!void {
        c.glLinkProgram(self.id);

        var success: c.GLint = 0;
        c.glGetProgramiv(self.id, c.GL_LINK_STATUS, &success);

        if (success == 0) {
            var info_log: [4096]u8 = undefined;
            var log_length: c.GLsizei = 0;
            c.glGetProgramInfoLog(self.id, 4096, &log_length, &info_log);

            log.err("Program linking failed - program id: {}", .{self.id});

            if (log_length > 0) {
                const log_str = info_log[0..@intCast(log_length)];
                log.err("Program error log:\n{s}", .{log_str});
            } else {
                log.err("No program info log available (log_length = 0)", .{});
            }

            return error.ProgramLinkFailed;
        }
    }

    pub fn use(self: Program) void {
        c.glUseProgram(self.id);
    }

    pub fn delete(self: Program) void {
        c.glDeleteProgram(self.id);
    }

    pub fn getUniformLocation(self: Program, name: [:0]const u8) c.GLint {
        return c.glGetUniformLocation(self.id, name.ptr);
    }

    pub fn getUniformBlockIndex(self: Program, name: [:0]const u8) c.GLuint {
        return c.glGetUniformBlockIndex(self.id, name.ptr);
    }

    pub fn uniformBlockBinding(self: Program, block_index: c.GLuint, binding_point: c.GLuint) void {
        c.glUniformBlockBinding(self.id, block_index, binding_point);
    }
};

/// Set a uniform int value (e.g., for texture unit bindings)
pub fn uniform1i(location: c.GLint, value: c.GLint) void {
    c.glUniform1i(location, value);
}

// ============================================================================
// Buffer Management
// ============================================================================

pub const Buffer = struct {
    id: c.GLuint,

    pub const Target = enum(c.GLenum) {
        array = c.GL_ARRAY_BUFFER,
        element_array = c.GL_ELEMENT_ARRAY_BUFFER,
        uniform = c.GL_UNIFORM_BUFFER,
        shader_storage = c.GL_SHADER_STORAGE_BUFFER,
    };

    pub const Usage = enum(c.GLenum) {
        stream_draw = c.GL_STREAM_DRAW,
        static_draw = c.GL_STATIC_DRAW,
        dynamic_draw = c.GL_DYNAMIC_DRAW,
    };

    pub fn create() Error!Buffer {
        var id: c.GLuint = 0;
        c.glGenBuffers(1, &id);
        if (id == 0) {
            try checkError();
            return error.InvalidOperation;
        }
        return .{ .id = id };
    }

    pub fn bind(self: Buffer, target: Target) void {
        c.glBindBuffer(@intFromEnum(target), self.id);
    }

    pub fn unbind(target: Target) void {
        c.glBindBuffer(@intFromEnum(target), 0);
    }

    pub fn setData(
        target: Target,
        size: usize,
        data: ?*const anyopaque,
        usage: Usage,
    ) void {
        c.glBufferData(
            @intFromEnum(target),
            @intCast(size),
            data,
            @intFromEnum(usage),
        );
    }

    pub fn setSubData(
        target: Target,
        offset: usize,
        size: usize,
        data: *const anyopaque,
    ) void {
        c.glBufferSubData(
            @intFromEnum(target),
            @intCast(offset),
            @intCast(size),
            data,
        );
    }

    pub fn bindBase(
        self: Buffer,
        target: Target,
        index: c.GLuint,
    ) void {
        c.glBindBufferBase(@intFromEnum(target), index, self.id);
    }

    pub fn delete(self: Buffer) void {
        c.glDeleteBuffers(1, &self.id);
    }
};

// ============================================================================
// Texture Management
// ============================================================================

pub const Texture = struct {
    id: c.GLuint,

    pub const Target = enum(c.GLenum) {
        texture_2d = c.GL_TEXTURE_2D,
    };

    pub const Format = enum(c.GLenum) {
        red = c.GL_RED,
        rg = c.GL_RG,
        rgb = c.GL_RGB,
        rgba = c.GL_RGBA,
    };

    pub const InternalFormat = enum(c.GLenum) {
        r8 = c.GL_R8,
        rg8 = c.GL_RG8,
        rgb8 = c.GL_RGB8,
        rgba8 = c.GL_RGBA8,
    };

    pub const Filter = enum(c.GLenum) {
        nearest = c.GL_NEAREST,
        linear = c.GL_LINEAR,
    };

    pub const Wrap = enum(c.GLenum) {
        repeat = c.GL_REPEAT,
        clamp_to_edge = c.GL_CLAMP_TO_EDGE,
    };

    pub const Parameter = enum(c.GLenum) {
        min_filter = c.GL_TEXTURE_MIN_FILTER,
        mag_filter = c.GL_TEXTURE_MAG_FILTER,
        wrap_s = c.GL_TEXTURE_WRAP_S,
        wrap_t = c.GL_TEXTURE_WRAP_T,
    };

    pub fn create() Error!Texture {
        var id: c.GLuint = 0;
        c.glGenTextures(1, &id);
        if (id == 0) {
            try checkError();
            return error.InvalidOperation;
        }
        return .{ .id = id };
    }

    pub fn bind(self: Texture, target: Target) void {
        c.glBindTexture(@intFromEnum(target), self.id);
    }

    pub fn unbind(target: Target) void {
        c.glBindTexture(@intFromEnum(target), 0);
    }

    pub fn parameter(target: Target, pname: Parameter, value: c.GLint) void {
        c.glTexParameteri(@intFromEnum(target), @intFromEnum(pname), value);
    }

    pub fn image2D(
        target: Target,
        level: c.GLint,
        internal_format: InternalFormat,
        width: c.GLsizei,
        height: c.GLsizei,
        format: Format,
        data: ?*const anyopaque,
    ) void {
        c.glTexImage2D(
            @intFromEnum(target),
            level,
            @intCast(@intFromEnum(internal_format)),
            width,
            height,
            0, // border (must be 0)
            @intFromEnum(format),
            c.GL_UNSIGNED_BYTE,
            data,
        );
    }

    pub fn subImage2D(
        target: Target,
        level: c.GLint,
        xoffset: c.GLint,
        yoffset: c.GLint,
        width: c.GLsizei,
        height: c.GLsizei,
        format: Format,
        data: *const anyopaque,
    ) void {
        c.glTexSubImage2D(
            @intFromEnum(target),
            level,
            xoffset,
            yoffset,
            width,
            height,
            @intFromEnum(format),
            c.GL_UNSIGNED_BYTE,
            data,
        );
    }

    pub fn active(unit: u32) void {
        c.glActiveTexture(@as(c.GLenum, c.GL_TEXTURE0) + @as(c.GLenum, unit));
    }

    pub fn delete(self: Texture) void {
        c.glDeleteTextures(1, &self.id);
    }
};

// ============================================================================
// Vertex Array Object (VAO)
// ============================================================================

pub const VertexArray = struct {
    id: c.GLuint,

    pub fn create() Error!VertexArray {
        var id: c.GLuint = 0;
        c.glGenVertexArrays(1, &id);
        if (id == 0) {
            try checkError();
            return error.InvalidOperation;
        }
        return .{ .id = id };
    }

    pub fn bind(self: VertexArray) void {
        c.glBindVertexArray(self.id);
    }

    pub fn unbind() void {
        c.glBindVertexArray(0);
    }

    pub fn delete(self: VertexArray) void {
        c.glDeleteVertexArrays(1, &self.id);
    }

    pub fn enableAttribArray(index: c.GLuint) void {
        c.glEnableVertexAttribArray(index);
    }

    pub fn disableAttribArray(index: c.GLuint) void {
        c.glDisableVertexAttribArray(index);
    }

    /// Set attribute pointer for float attributes
    pub fn attribPointer(
        index: c.GLuint,
        size: c.GLint,
        attr_type: c.GLenum,
        normalized: bool,
        stride: c.GLsizei,
        offset: usize,
    ) void {
        c.glVertexAttribPointer(
            index,
            size,
            attr_type,
            if (normalized) c.GL_TRUE else c.GL_FALSE,
            stride,
            @ptrFromInt(offset),
        );
    }

    /// Set attribute pointer for integer attributes
    pub fn attribIPointer(
        index: c.GLuint,
        size: c.GLint,
        attr_type: c.GLenum,
        stride: c.GLsizei,
        offset: usize,
    ) void {
        c.glVertexAttribIPointer(
            index,
            size,
            attr_type,
            stride,
            @ptrFromInt(offset),
        );
    }

    /// Set divisor for instanced rendering
    pub fn attribDivisor(index: c.GLuint, divisor: c.GLuint) void {
        c.glVertexAttribDivisor(index, divisor);
    }
};

// ============================================================================
// Framebuffer
// ============================================================================

pub const Framebuffer = struct {
    id: c.GLuint,

    pub const Target = enum(c.GLenum) {
        framebuffer = c.GL_FRAMEBUFFER,
        read_framebuffer = c.GL_READ_FRAMEBUFFER,
        draw_framebuffer = c.GL_DRAW_FRAMEBUFFER,
    };

    pub fn create() Error!Framebuffer {
        var id: c.GLuint = 0;
        c.glGenFramebuffers(1, &id);
        if (id == 0) {
            try checkError();
            return error.InvalidOperation;
        }
        return .{ .id = id };
    }

    pub fn bind(self: Framebuffer, target: Target) void {
        c.glBindFramebuffer(@intFromEnum(target), self.id);
    }

    pub fn unbind(target: Target) void {
        c.glBindFramebuffer(@intFromEnum(target), 0);
    }

    pub fn delete(self: Framebuffer) void {
        c.glDeleteFramebuffers(1, &self.id);
    }
};

// ============================================================================
// Drawing Functions
// ============================================================================

pub fn clearColor(r: f32, g: f32, b: f32, a: f32) void {
    c.glClearColor(r, g, b, a);
}

pub fn clear(mask: c.GLbitfield) void {
    c.glClear(mask);
}

pub fn viewport(x: c.GLint, y: c.GLint, width: c.GLsizei, height: c.GLsizei) void {
    c.glViewport(x, y, width, height);
}

pub fn drawArrays(mode: c.GLenum, first: c.GLint, count: c.GLsizei) void {
    c.glDrawArrays(mode, first, count);
}

pub fn drawArraysInstanced(
    mode: c.GLenum,
    first: c.GLint,
    count: c.GLsizei,
    instance_count: c.GLsizei,
) void {
    c.glDrawArraysInstanced(mode, first, count, instance_count);
}

pub fn enable(cap: c.GLenum) void {
    c.glEnable(cap);
}

pub fn disable(cap: c.GLenum) void {
    c.glDisable(cap);
}

pub fn blendFunc(sfactor: c.GLenum, dfactor: c.GLenum) void {
    c.glBlendFunc(sfactor, dfactor);
}

pub fn blendFuncSeparate(
    src_rgb: c.GLenum,
    dst_rgb: c.GLenum,
    src_alpha: c.GLenum,
    dst_alpha: c.GLenum,
) void {
    c.glBlendFuncSeparate(src_rgb, dst_rgb, src_alpha, dst_alpha);
}

pub fn blendEquation(mode: c.GLenum) void {
    c.glBlendEquation(mode);
}

// ============================================================================
// Constants commonly used
// ============================================================================

pub const GL_TRIANGLES = c.GL_TRIANGLES;
pub const GL_TRIANGLE_STRIP = c.GL_TRIANGLE_STRIP;
pub const GL_COLOR_BUFFER_BIT = c.GL_COLOR_BUFFER_BIT;
pub const GL_DEPTH_BUFFER_BIT = c.GL_DEPTH_BUFFER_BIT;
pub const GL_BLEND = c.GL_BLEND;
pub const GL_ONE = c.GL_ONE;
pub const GL_ZERO = c.GL_ZERO;
pub const GL_SRC_ALPHA = c.GL_SRC_ALPHA;
pub const GL_ONE_MINUS_SRC_ALPHA = c.GL_ONE_MINUS_SRC_ALPHA;
pub const GL_FUNC_ADD = c.GL_FUNC_ADD;
pub const GL_UNSIGNED_BYTE = c.GL_UNSIGNED_BYTE;
pub const GL_UNSIGNED_SHORT = c.GL_UNSIGNED_SHORT;
pub const GL_UNSIGNED_INT = c.GL_UNSIGNED_INT;
pub const GL_BYTE = c.GL_BYTE;
pub const GL_SHORT = c.GL_SHORT;
pub const GL_INT = c.GL_INT;
pub const GL_FLOAT = c.GL_FLOAT;
