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

// Custom logging function for Android
fn androidLogFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime level.asText();
    const prefix = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";

    var buf: [4096]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, level_txt ++ prefix ++ format, args) catch {
        _ = c.__android_log_print(c.ANDROID_LOG_ERROR, "GhosttyRenderer", "Log format error");
        return;
    };

    const android_level = switch (level) {
        .err => c.ANDROID_LOG_ERROR,
        .warn => c.ANDROID_LOG_WARN,
        .info => c.ANDROID_LOG_INFO,
        .debug => c.ANDROID_LOG_DEBUG,
    };

    _ = c.__android_log_print(android_level, "GhosttyRenderer", "%s", msg.ptr);
}

// Configure std.log to output to Android logcat
pub const std_options: std.Options = .{
    .logFn = androidLogFn,
};

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
    surface_sized: bool = false,  // Track if surface has been sized at least once
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

    log.info("nativeOnSurfaceCreated - OpenGL context (re)created", .{});

    // Get OpenGL version
    const version = c.glGetString(c.GL_VERSION);
    const renderer_name = c.glGetString(c.GL_RENDERER);
    const vendor = c.glGetString(c.GL_VENDOR);

    if (version) |v| {
        log.info("OpenGL Version: {s}", .{v});
    }
    if (renderer_name) |r| {
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

    // IMPORTANT: When onSurfaceCreated is called, the OpenGL context has been (re)created.
    // This happens when:
    // - The app first starts
    // - The app returns from background
    // - The OpenGL context is lost for any reason
    //
    // When the context is recreated, all OpenGL objects (shaders, programs, VAOs, textures, buffers)
    // become invalid and must be recreated.

    // Clean up the old renderer if it exists (its OpenGL objects are now invalid)
    if (renderer_state.renderer) |*renderer| {
        log.info("Cleaning up old renderer (OpenGL context was recreated)", .{});
        renderer.deinit();
        renderer_state.renderer = null;
    }

    // Reset initialization state so onSurfaceChanged will recreate the renderer
    renderer_state.initialized = false;
    renderer_state.surface_sized = false;

    log.info("OpenGL context ready, renderer will be recreated in onSurfaceChanged", .{});
}

/// Called when OpenGL surface size changes
/// Java signature: void nativeOnSurfaceChanged(int width, int height, int dpi)
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeOnSurfaceChanged(
    env: *c.JNIEnv,
    obj: c.jobject,
    width: c.jint,
    height: c.jint,
    dpi: c.jint,
) void {
    _ = env;
    _ = obj;

    log.info("nativeOnSurfaceChanged: {d}x{d} at {d} DPI", .{ width, height, dpi });

    // Note: glViewport will be set by the renderer to match the expanded projection matrix
    // This ensures viewport and projection dimensions are in sync to avoid GL errors

    // Mark that surface has been sized at least once
    renderer_state.surface_sized = true;

    // Initialize renderer on first surface change (now we have real dimensions!)
    if (!renderer_state.initialized) {
        log.info("Initializing renderer with actual surface dimensions: {d}x{d} at {d} DPI", .{ width, height, dpi });

        const allocator = gpa.allocator();
        renderer_state.renderer = Renderer.init(allocator, @intCast(width), @intCast(height), @intCast(dpi)) catch |err| {
            log.err("Failed to initialize renderer: {}", .{err});
            return;
        };
        renderer_state.initialized = true;

        log.info("Renderer initialized successfully with correct dimensions", .{});
        log.info("Viewport set to {d}x{d}", .{ width, height });
        return; // Don't resize on first init - we just initialized with correct size!
    }

    // Only resize if dimensions actually changed
    if (renderer_state.renderer) |*renderer| {
        const current_size = .{ .width = renderer.width, .height = renderer.height };
        const new_size = .{ .width = @as(u32, @intCast(width)), .height = @as(u32, @intCast(height)) };

        if (current_size.width != new_size.width or current_size.height != new_size.height) {
            log.info("Surface dimensions changed, resizing renderer", .{});
            renderer.resize(new_size.width, new_size.height) catch |err| {
                log.err("Failed to resize renderer: {}", .{err});
                return;
            };
            log.info("Renderer resized to {d}x{d}", .{ width, height });
        } else {
            log.debug("Surface dimensions unchanged, skipping resize", .{});
        }
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

/// Set font size and rebuild font atlas
/// Java signature: void nativeSetFontSize(int fontSize)
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeSetFontSize(
    env: *c.JNIEnv,
    obj: c.jobject,
    font_size: c.jint,
) void {
    _ = env;
    _ = obj;

    log.info("nativeSetFontSize: {d}px", .{font_size});

    if (!renderer_state.initialized) {
        log.warn("Attempted to set font size before renderer initialized", .{});
        return;
    }

    if (renderer_state.renderer) |*renderer| {
        renderer.updateFontSize(@intCast(font_size)) catch |err| {
            log.err("Failed to update font size: {}", .{err});
            return;
        };
        log.info("Font size updated successfully to {d}px", .{font_size});
    } else {
        log.warn("Renderer not initialized", .{});
    }
}

/// Process ANSI input (inject ANSI escape sequences into the VT emulator)
/// Java signature: void nativeProcessInput(String ansiSequence)
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeProcessInput(
    env: *c.JNIEnv,
    obj: c.jobject,
    ansiSequence: c.jstring,
) void {
    _ = obj;

    log.info("nativeProcessInput called", .{});

    if (!renderer_state.initialized) {
        log.warn("Attempted to process input before renderer initialized", .{});
        return;
    }

    if (renderer_state.renderer) |*renderer| {
        // Convert JNI string to Zig string
        var buffer: [8192]u8 = undefined;
        const input_data = jni.getJString(env, ansiSequence, &buffer) catch |err| {
            log.err("Failed to get JNI string: {}", .{err});
            return;
        };

        log.debug("Processing {} bytes of ANSI input", .{input_data.len});

        // Feed the input to the terminal manager
        renderer.terminal_manager.processInput(input_data) catch |err| {
            log.err("Failed to process input: {}", .{err});
            return;
        };

        log.debug("Input processed successfully", .{});
    } else {
        log.warn("Renderer not initialized", .{});
    }
}

// ============================================================================
// Scrolling JNI Methods
// ============================================================================

/// Get the number of scrollback rows available
/// Java signature: int nativeGetScrollbackRows()
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeGetScrollbackRows(
    env: *c.JNIEnv,
    obj: c.jobject,
) c.jint {
    _ = env;
    _ = obj;

    if (!renderer_state.initialized) {
        log.warn("Attempted to get scrollback rows before renderer initialized", .{});
        return 0;
    }

    if (renderer_state.renderer) |*renderer| {
        const rows = renderer.getScrollbackRows();
        return @intCast(rows);
    }

    return 0;
}

/// Get the font line spacing (cell height) for scroll calculations
/// Java signature: float nativeGetFontLineSpacing()
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeGetFontLineSpacing(
    env: *c.JNIEnv,
    obj: c.jobject,
) c.jfloat {
    _ = env;
    _ = obj;

    if (!renderer_state.initialized) {
        log.warn("Attempted to get font line spacing before renderer initialized", .{});
        return 20.0; // Default fallback
    }

    if (renderer_state.renderer) |*renderer| {
        return renderer.getFontLineSpacing();
    }

    return 20.0; // Default fallback
}

/// Scroll the viewport by a delta number of rows
/// Positive delta scrolls down (towards newer content/active area)
/// Negative delta scrolls up (towards older content/scrollback)
/// Java signature: void nativeScrollDelta(int delta)
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeScrollDelta(
    env: *c.JNIEnv,
    obj: c.jobject,
    delta: c.jint,
) void {
    _ = env;
    _ = obj;

    if (!renderer_state.initialized) {
        log.warn("Attempted to scroll before renderer initialized", .{});
        return;
    }

    if (renderer_state.renderer) |*renderer| {
        renderer.scrollDelta(delta);
        log.debug("Scrolled viewport by {} rows", .{delta});
    }
}

/// Check if viewport is at the bottom (following active area)
/// Java signature: boolean nativeIsViewportAtBottom()
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeIsViewportAtBottom(
    env: *c.JNIEnv,
    obj: c.jobject,
) c.jboolean {
    _ = env;
    _ = obj;

    if (!renderer_state.initialized) {
        return c.JNI_TRUE; // Default to bottom when not initialized
    }

    if (renderer_state.renderer) |*renderer| {
        return if (renderer.isViewportAtBottom()) c.JNI_TRUE else c.JNI_FALSE;
    }

    return c.JNI_TRUE;
}

/// Get the current scroll offset from the top (0 = at top of scrollback)
/// Java signature: int nativeGetViewportOffset()
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeGetViewportOffset(
    env: *c.JNIEnv,
    obj: c.jobject,
) c.jint {
    _ = env;
    _ = obj;

    if (!renderer_state.initialized) {
        return 0;
    }

    if (renderer_state.renderer) |*renderer| {
        const offset = renderer.getViewportOffset();
        return @intCast(offset);
    }

    return 0;
}

/// Scroll viewport to the bottom (active area)
/// Java signature: void nativeScrollToBottom()
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeScrollToBottom(
    env: *c.JNIEnv,
    obj: c.jobject,
) void {
    _ = env;
    _ = obj;

    if (!renderer_state.initialized) {
        log.warn("Attempted to scroll to bottom before renderer initialized", .{});
        return;
    }

    if (renderer_state.renderer) |*renderer| {
        renderer.scrollToBottom();
        log.debug("Scrolled viewport to bottom", .{});
    }
}

/// Set the visual scroll pixel offset for smooth sub-row scrolling
/// This offset is applied in the shaders to shift content smoothly
/// between row boundaries during scroll animations.
/// Java signature: void nativeSetScrollPixelOffset(float offset)
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeSetScrollPixelOffset(
    env: *c.JNIEnv,
    obj: c.jobject,
    offset: c.jfloat,
) void {
    _ = env;
    _ = obj;

    if (!renderer_state.initialized) {
        return;
    }

    if (renderer_state.renderer) |*renderer| {
        renderer.setScrollPixelOffset(offset);
    }
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
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeSetFontSize;
    // Scrolling methods
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeGetScrollbackRows;
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeGetFontLineSpacing;
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeScrollDelta;
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeIsViewportAtBottom;
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeGetViewportOffset;
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeScrollToBottom;
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeSetScrollPixelOffset;
}
