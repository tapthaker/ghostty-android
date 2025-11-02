///! Rendering pipeline management for OpenGL ES 3.1
///!
///! A pipeline encapsulates a shader program, VAO, and associated state
///! for a specific rendering operation.

const std = @import("std");
const gl = @import("gl_es.zig");

const Self = @This();

/// Options for initializing a render pipeline.
pub const Options = struct {
    /// GLSL source of the vertex shader
    vertex_src: [:0]const u8,

    /// GLSL source of the fragment shader
    fragment_src: [:0]const u8,

    /// Vertex step function (how attributes are consumed)
    step_fn: StepFunction = .per_vertex,

    /// Whether to enable blending for this pipeline
    blending_enabled: bool = true,

    pub const StepFunction = enum {
        constant,     // All vertices get the same value
        per_vertex,   // Each vertex gets its own value (divisor = 0)
        per_instance, // Each instance gets its own value (divisor = 1)
    };
};

/// The shader program for this pipeline
program: gl.Program,

/// The vertex array object for this pipeline
vao: gl.VertexArray,

/// Stride of vertex attributes (0 if no attributes)
stride: usize,

/// Whether blending is enabled for this pipeline
blending_enabled: bool,

/// Initialize a pipeline with optional vertex attributes.
///
/// If VertexAttributes is null, no vertex attributes are configured
/// (for example, for full-screen shaders that generate vertices in the shader).
///
/// If VertexAttributes is provided, vertex attributes are automatically
/// configured based on the struct fields.
pub fn init(
    comptime VertexAttributes: ?type,
    opts: Options,
) !Self {
    // Compile and link shader program
    const program = try gl.Program.create();
    errdefer program.delete();

    const vertex_shader = try gl.Shader.create(.vertex);
    defer vertex_shader.delete();
    vertex_shader.source(opts.vertex_src);
    try vertex_shader.compile();

    const fragment_shader = try gl.Shader.create(.fragment);
    defer fragment_shader.delete();
    fragment_shader.source(opts.fragment_src);
    try fragment_shader.compile();

    program.attachShader(vertex_shader);
    program.attachShader(fragment_shader);
    try program.link();

    // Create VAO
    const vao = try gl.VertexArray.create();
    errdefer vao.delete();

    // Configure vertex attributes if provided
    if (VertexAttributes) |VA| {
        vao.bind();
        defer gl.VertexArray.unbind();
        try autoConfigureAttributes(VA, opts.step_fn);
    }

    return .{
        .program = program,
        .vao = vao,
        .stride = if (VertexAttributes) |VA| @sizeOf(VA) else 0,
        .blending_enabled = opts.blending_enabled,
    };
}

pub fn deinit(self: *const Self) void {
    self.program.delete();
    self.vao.delete();
}

/// Automatically configure vertex attributes based on a struct type.
/// This inspects the struct fields and sets up appropriate vertex attribute
/// pointers based on field types and offsets.
fn autoConfigureAttributes(
    comptime T: type,
    step_fn: Options.StepFunction,
) !void {
    const divisor: u32 = switch (step_fn) {
        .per_vertex => 0,
        .per_instance => 1,
        .constant => std.math.maxInt(u32),
    };

    const stride: gl.c.GLsizei = @intCast(@sizeOf(T));

    inline for (@typeInfo(T).@"struct".fields, 0..) |field, i| {
        const index: u32 = @intCast(i);
        gl.VertexArray.enableAttribArray(index);
        gl.VertexArray.attribDivisor(index, divisor);

        const offset = @offsetOf(T, field.name);

        // Get the underlying type (unwrap packed structs and enums)
        const FT = switch (@typeInfo(field.type)) {
            .@"struct" => |s| s.backing_integer orelse field.type,
            .@"enum" => |e| e.tag_type,
            else => field.type,
        };

        // Determine size and inner type for arrays
        const size, const IT = switch (@typeInfo(FT)) {
            .array => |a| .{ @as(gl.c.GLint, @intCast(a.len)), a.child },
            else => .{ @as(gl.c.GLint, 1), FT },
        };

        // Configure attribute pointer based on type
        switch (IT) {
            u8 => gl.VertexArray.attribIPointer(
                index,
                size,
                gl.GL_UNSIGNED_BYTE,
                stride,
                offset,
            ),
            u16 => gl.VertexArray.attribIPointer(
                index,
                size,
                gl.GL_UNSIGNED_SHORT,
                stride,
                offset,
            ),
            u32 => gl.VertexArray.attribIPointer(
                index,
                size,
                gl.GL_UNSIGNED_INT,
                stride,
                offset,
            ),
            i8 => gl.VertexArray.attribIPointer(
                index,
                size,
                gl.GL_BYTE,
                stride,
                offset,
            ),
            i16 => gl.VertexArray.attribIPointer(
                index,
                size,
                gl.GL_SHORT,
                stride,
                offset,
            ),
            i32 => gl.VertexArray.attribIPointer(
                index,
                size,
                gl.GL_INT,
                stride,
                offset,
            ),
            f32 => gl.VertexArray.attribPointer(
                index,
                size,
                gl.GL_FLOAT,
                false,
                stride,
                offset,
            ),
            else => @compileError("Unsupported vertex attribute type: " ++ @typeName(IT)),
        }
    }
}

/// Use this pipeline for rendering.
/// Binds the program and VAO, and configures blending state.
pub fn use(self: Self) void {
    self.program.use();
    self.vao.bind();

    if (self.blending_enabled) {
        gl.enable(gl.GL_BLEND);
        // Standard alpha blending: src_alpha, 1-src_alpha
        gl.blendFuncSeparate(
            gl.GL_ONE,
            gl.GL_ONE_MINUS_SRC_ALPHA,
            gl.GL_ONE,
            gl.GL_ONE_MINUS_SRC_ALPHA,
        );
        gl.blendEquation(gl.GL_FUNC_ADD);
    } else {
        gl.disable(gl.GL_BLEND);
    }
}
