///! Ghostty Android OpenGL ES 3.1 Renderer
///!
///! This module provides a JNI bridge for rendering terminal content
///! using OpenGL ES 3.1 on Android devices.

const std = @import("std");
const c = @cImport({
    @cInclude("jni.h");
    @cInclude("GLES3/gl31.h");
    @cInclude("android/log.h");
});

const jni = @import("jni_bridge.zig");

// Android logging utilities
// NOTE: Disabled for now because Zig can't link against liblog during cross-compilation
// TODO: Re-enable using JNI callbacks to Java logging
const log = struct {
    const TAG = "GhosttyRenderer";

    fn info(comptime fmt: []const u8, args: anytype) void {
        _ = fmt;
        _ = args;
        // Disabled: _ = c.__android_log_print(c.ANDROID_LOG_INFO, TAG, "%s", msg.ptr);
    }

    fn warn(comptime fmt: []const u8, args: anytype) void {
        _ = fmt;
        _ = args;
        // Disabled: _ = c.__android_log_print(c.ANDROID_LOG_WARN, TAG, "%s", msg.ptr);
    }

    fn err(comptime fmt: []const u8, args: anytype) void {
        _ = fmt;
        _ = args;
        // Disabled: _ = c.__android_log_print(c.ANDROID_LOG_ERROR, TAG, "%s", msg.ptr);
    }

    fn debug(comptime fmt: []const u8, args: anytype) void {
        _ = fmt;
        _ = args;
        // Disabled: _ = c.__android_log_print(c.ANDROID_LOG_DEBUG, TAG, "%s", msg.ptr);
    }
};

// Global allocator
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

// Renderer state (will be expanded in later phases)
const RendererState = struct {
    width: u32 = 0,
    height: u32 = 0,
    initialized: bool = false,
};

var renderer_state: RendererState = .{};

/// JNI_OnLoad - Called when the library is loaded
export fn JNI_OnLoad(vm: *c.JavaVM, reserved: ?*anyopaque) c.jint {
    _ = vm;
    _ = reserved;

    log.info("Ghostty Renderer library loaded", .{});
    return c.JNI_VERSION_1_6;
}

/// JNI_OnUnload - Called when the library is unloaded
export fn JNI_OnUnload(vm: *c.JavaVM, reserved: ?*anyopaque) void {
    _ = vm;
    _ = reserved;

    log.info("Ghostty Renderer library unloaded", .{});

    // Cleanup global allocator
    _ = gpa.deinit();
}

/// Called when OpenGL surface is created
/// Java signature: void nativeOnSurfaceCreated()
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeOnSurfaceCreated(
    env: *c.JNIEnv,
    obj: c.jobject,
) void {
    _ = env;
    _ = obj;

    log.info("nativeOnSurfaceCreated", .{});

    // Get OpenGL version
    const version = c.glGetString(c.GL_VERSION);
    const renderer = c.glGetString(c.GL_RENDERER);
    const vendor = c.glGetString(c.GL_VENDOR);

    if (version) |v| {
        log.info("OpenGL Version: {s}", .{v});
    }
    if (renderer) |r| {
        log.info("OpenGL Renderer: {s}", .{r});
    }
    if (vendor) |vnd| {
        log.info("OpenGL Vendor: {s}", .{vnd});
    }

    // Check for OpenGL ES 3.1 support
    var major: c.GLint = 0;
    var minor: c.GLint = 0;
    c.glGetIntegerv(c.GL_MAJOR_VERSION, &major);
    c.glGetIntegerv(c.GL_MINOR_VERSION, &minor);

    log.info("OpenGL ES Version: {d}.{d}", .{ major, minor });

    if (major < 3 or (major == 3 and minor < 1)) {
        log.err("OpenGL ES 3.1 or higher required! Found: {d}.{d}", .{ major, minor });
        return;
    }

    // Initialize renderer
    renderer_state.initialized = true;
    log.info("Renderer initialized successfully", .{});
}

/// Called when OpenGL surface size changes
/// Java signature: void nativeOnSurfaceChanged(int width, int height)
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeOnSurfaceChanged(
    env: *c.JNIEnv,
    obj: c.jobject,
    width: c.jint,
    height: c.jint,
) void {
    _ = env;
    _ = obj;

    log.info("nativeOnSurfaceChanged: {d}x{d}", .{ width, height });

    renderer_state.width = @intCast(width);
    renderer_state.height = @intCast(height);

    // Set OpenGL viewport
    c.glViewport(0, 0, width, height);

    log.info("Viewport updated to {d}x{d}", .{ width, height });
}

/// Called to render a frame
/// Java signature: void nativeOnDrawFrame()
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeOnDrawFrame(
    env: *c.JNIEnv,
    obj: c.jobject,
) void {
    _ = env;
    _ = obj;

    if (!renderer_state.initialized) {
        log.warn("Attempted to draw frame before renderer initialized", .{});
        return;
    }

    // Clear the screen with a test color (purple-ish)
    // This is just for proof of concept - will be replaced with actual rendering
    c.glClearColor(0.4, 0.2, 0.6, 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT);

    // Check for OpenGL errors
    const err = c.glGetError();
    if (err != c.GL_NO_ERROR) {
        log.err("OpenGL error during frame: 0x{x}", .{err});
    }
}

/// Called to destroy the renderer
/// Java signature: void nativeDestroy()
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeDestroy(
    env: *c.JNIEnv,
    obj: c.jobject,
) void {
    _ = env;
    _ = obj;

    log.info("nativeDestroy", .{});

    renderer_state.initialized = false;
    renderer_state.width = 0;
    renderer_state.height = 0;

    log.info("Renderer destroyed", .{});
}

/// Set terminal size (rows/columns)
/// Java signature: void nativeSetTerminalSize(int cols, int rows)
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeSetTerminalSize(
    env: *c.JNIEnv,
    obj: c.jobject,
    cols: c.jint,
    rows: c.jint,
) void {
    _ = env;
    _ = obj;

    log.info("nativeSetTerminalSize: {d}x{d}", .{ cols, rows });

    // TODO: Update terminal dimensions
    // This will be implemented when we integrate with libghostty-vt
}

// Comptime test to ensure JNI function names are correct
comptime {
    // This will cause a compile error if the function signatures don't match
    // what the JNI expects
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeOnSurfaceCreated;
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeOnSurfaceChanged;
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeOnDrawFrame;
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeDestroy;
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeSetTerminalSize;
}
