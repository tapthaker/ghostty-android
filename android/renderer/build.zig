const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Validate this is an Android target
    const target_info = target.result;
    if (target_info.os.tag != .linux or target_info.abi != .android) {
        std.log.warn("Warning: Target should be Android (e.g., aarch64-linux-android)", .{});
    }

    // Get FreeType dependency
    // Note: libpng disabled - CBDT color emoji won't work (uses PNG bitmaps)
    // Using monochrome Noto Emoji or system fallback instead
    const freetype_dep = b.dependency("freetype", .{
        .target = target,
        .optimize = optimize,
        .@"enable-libpng" = false,
    });

    // Get libghostty-vt dependency
    const vt_dep = b.dependency("ghostty-vt", .{
        .target = target,
        .optimize = optimize,
    });

    // Create a module for the library
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add FreeType module
    lib_mod.addImport("freetype", freetype_dep.module("freetype"));

    // Add libghostty-vt module (using the Zig module, not C ABI)
    lib_mod.addImport("ghostty-vt", vt_dep.module("ghostty-vt"));

    // Create the shared library for Android
    const lib = b.addLibrary(.{
        .name = "ghostty_renderer",
        .root_module = lib_mod,
        .linkage = .dynamic,
    });

    // Link libc (required for JNI)
    lib.linkLibC();

    // Link FreeType library
    lib.linkLibrary(freetype_dep.artifact("freetype"));

    // Note: We need OpenGL ES 3.1 symbols, but can't link them during cross-compilation.
    // The symbols will be left undefined and must be resolved by the Android dynamic linker.
    // We'll use a post-build step to add libGLESv3.so to DT_NEEDED section.

    // Add include paths for libghostty-vt headers (if needed in future)
    const ghostty_include = b.path("../../libghostty-vt/include");
    lib.addIncludePath(ghostty_include);

    // Install the shared library
    b.installArtifact(lib);

    // Create a test step (for future unit tests)
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_unit_tests = b.addTest(.{
        .name = "renderer_tests",
        .root_module = test_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
