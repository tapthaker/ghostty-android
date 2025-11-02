///! Shader compilation and program linking for OpenGL ES 3.1
///!
///! This module handles compiling GLSL shader source code and linking
///! shader programs.

const std = @import("std");
const gl = @import("gl_es.zig");

const log = std.log.scoped(.shader);

/// Create a shader program from vertex and fragment shader source code.
/// The shaders are compiled, linked, and validated. The individual shader
/// objects are deleted after linking (the program retains the compiled code).
pub fn createProgram(
    vertex_src: [:0]const u8,
    fragment_src: [:0]const u8,
) !gl.Program {
    // Compile vertex shader
    const vertex_shader = try gl.Shader.create(.vertex);
    defer vertex_shader.delete();

    vertex_shader.source(vertex_src);
    try vertex_shader.compile();

    // Compile fragment shader
    const fragment_shader = try gl.Shader.create(.fragment);
    defer fragment_shader.delete();

    fragment_shader.source(fragment_src);
    try fragment_shader.compile();

    // Create and link program
    const program = try gl.Program.create();
    errdefer program.delete();

    program.attachShader(vertex_shader);
    program.attachShader(fragment_shader);
    try program.link();

    log.debug("Shader program created successfully (id={})", .{program.id});

    return program;
}

/// Load shader code from embedded files, processing `#include` directives.
///
/// Comptime only - this is used to embed shader code at compile time and
/// process any #include directives to inline included files.
pub fn loadShaderCode(comptime path: []const u8) [:0]const u8 {
    return comptime processIncludes(@embedFile(path), std.fs.path.dirname(path).?);
}

/// Process #include directives in shader source code.
/// Used by loadShaderCode to inline included files.
fn processIncludes(comptime contents: [:0]const u8, comptime basedir: []const u8) [:0]const u8 {
    @setEvalBranchQuota(100_000);
    var i: usize = 0;
    while (i < contents.len) {
        if (std.mem.startsWith(u8, contents[i..], "#include")) {
            std.debug.assert(std.mem.startsWith(u8, contents[i..], "#include \""));
            const start = i + "#include \"".len;
            const end = std.mem.indexOfScalarPos(u8, contents, start, '"').?;
            return std.fmt.comptimePrint(
                "{s}{s}{s}",
                .{
                    contents[0..i],
                    @embedFile(basedir ++ "/" ++ contents[start..end]),
                    processIncludes(contents[end + 1 ..], basedir),
                },
            );
        }
        if (std.mem.indexOfPos(u8, contents, i, "\n#")) |j| {
            i = (j + 1);
        } else {
            break;
        }
    }
    return contents;
}
