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
const Renderer = @import("renderer.zig");

// Android logging utilities
// NOTE: liblog.so is loaded via DT_NEEDED (added by patchelf)
const log = struct {
    const TAG = "GhosttyRendererNative";

    fn info(comptime fmt: []const u8, args: anytype) void {
        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch "Log format error";
        _ = c.__android_log_print(c.ANDROID_LOG_INFO, TAG, "%s", msg.ptr);
    }

    fn warn(comptime fmt: []const u8, args: anytype) void {
        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch "Log format error";
        _ = c.__android_log_print(c.ANDROID_LOG_WARN, TAG, "%s", msg.ptr);
    }

    fn err(comptime fmt: []const u8, args: anytype) void {
        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch "Log format error";
        _ = c.__android_log_print(c.ANDROID_LOG_ERROR, TAG, "%s", msg.ptr);
    }

    fn debug(comptime fmt: []const u8, args: anytype) void {
        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch "Log format error";
        _ = c.__android_log_print(c.ANDROID_LOG_DEBUG, TAG, "%s", msg.ptr);
    }
};

// Global allocator
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

// Renderer state
const RendererState = struct {
    renderer: ?Renderer = null,
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
    const allocator = gpa.allocator();
    renderer_state.renderer = Renderer.init(allocator) catch |err| {
        log.err("Failed to initialize renderer: {}", .{err});
        return;
    };
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

    // Set OpenGL viewport
    c.glViewport(0, 0, width, height);

    // Update renderer with new dimensions
    if (renderer_state.renderer) |*renderer| {
        renderer.resize(@intCast(width), @intCast(height)) catch |err| {
            log.err("Failed to resize renderer: {}", .{err});
            return;
        };
    }

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

    // Render using the renderer module
    if (renderer_state.renderer) |*renderer| {
        renderer.render() catch |err| {
            log.err("Failed to render frame: {}", .{err});
            return;
        };
    } else {
        log.warn("Renderer not initialized", .{});
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

    if (renderer_state.renderer) |*renderer| {
        renderer.deinit();
    }

    renderer_state.initialized = false;
    renderer_state.renderer = null;

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
