const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Validate this is an Android target
    const target_info = target.result;
    if (target_info.os.tag != .linux or target_info.abi != .android) {
        std.log.warn("Warning: Target should be Android (e.g., aarch64-linux-android)", .{});
    }

    // Create a module for the renderer
    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create the shared library for Android with the module
    const lib = b.addLibrary(.{
        .name = "ghostty_renderer",
        .linkage = .dynamic,
        .root_module = mod,
    });

    // Link libc (required for JNI)
    lib.linkLibC();

    // Note: We need OpenGL ES 3.1 symbols, but can't link them during cross-compilation.
    // The symbols will be left undefined and must be resolved by the Android dynamic linker.
    // We'll use a post-build step to add libGLESv3.so to DT_NEEDED section.

    // Add include paths for libghostty-vt headers (if needed in future)
    const ghostty_include = b.path("../../libghostty-vt/include");
    lib.addIncludePath(ghostty_include);

    // Install the shared library
    b.installArtifact(lib);

    // Create a test step (for future unit tests)
    // Use the same module for tests
    const lib_unit_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
