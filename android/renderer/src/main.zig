///! Ghostty Android OpenGL ES 3.1 Renderer
///!
///! This module provides a JNI bridge for rendering terminal content
///! using OpenGL ES 3.1 on Android devices.
///!
///! Each GhosttyRenderer instance in Kotlin has its own native handle,
///! allowing multiple GLSurfaceViews (e.g., in RecyclerView) to coexist.

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

// Renderer state - now stored per-instance
const RendererState = struct {
    renderer: ?Renderer = null,
    initialized: bool = false,
    surface_sized: bool = false, // Track if surface has been sized at least once
    initial_font_size: u32 = 0, // Initial font size in pixels (0 = use default)
    current_font_size: u32 = 0, // Current font size in pixels (for change detection)
};

// Map of handle ID -> RendererState
// Using AutoHashMap with u64 keys for the handle
var renderer_map: std.AutoHashMap(u64, *RendererState) = undefined;
var renderer_map_initialized: bool = false;
var next_handle: u64 = 1;
var map_mutex: std.Thread.Mutex = .{};

fn ensureMapInitialized() void {
    if (!renderer_map_initialized) {
        renderer_map = std.AutoHashMap(u64, *RendererState).init(gpa.allocator());
        renderer_map_initialized = true;
    }
}

fn getRendererState(handle: u64) ?*RendererState {
    map_mutex.lock();
    defer map_mutex.unlock();

    ensureMapInitialized();
    return renderer_map.get(handle);
}

fn createRendererState() !u64 {
    map_mutex.lock();
    defer map_mutex.unlock();

    ensureMapInitialized();

    const allocator = gpa.allocator();
    const state = try allocator.create(RendererState);
    state.* = .{};

    const handle = next_handle;
    next_handle += 1;

    try renderer_map.put(handle, state);
    log.info("Created renderer state with handle {d}", .{handle});
    return handle;
}

fn destroyRendererState(handle: u64) void {
    map_mutex.lock();
    defer map_mutex.unlock();

    ensureMapInitialized();

    if (renderer_map.fetchRemove(handle)) |kv| {
        const state = kv.value;
        if (state.renderer) |*renderer| {
            renderer.deinit();
        }
        gpa.allocator().destroy(state);
        log.info("Destroyed renderer state with handle {d}", .{handle});
    }
}

// Helper to get the native handle from the Java object
fn getNativeHandle(env: *c.JNIEnv, obj: c.jobject) u64 {
    const env_vtable = env.*.?;
    const cls = env_vtable.*.GetObjectClass.?(env, obj);
    if (cls == null) {
        log.err("Failed to get object class", .{});
        return 0;
    }

    const field_id = env_vtable.*.GetFieldID.?(env, cls, "nativeHandle", "J");
    if (field_id == null) {
        log.err("Failed to get nativeHandle field ID", .{});
        return 0;
    }

    const handle = env_vtable.*.GetLongField.?(env, obj, field_id);
    return @bitCast(handle);
}

// Helper to set the native handle on the Java object
fn setNativeHandle(env: *c.JNIEnv, obj: c.jobject, handle: u64) void {
    const env_vtable = env.*.?;
    const cls = env_vtable.*.GetObjectClass.?(env, obj);
    if (cls == null) {
        log.err("Failed to get object class for setting handle", .{});
        return;
    }

    const field_id = env_vtable.*.GetFieldID.?(env, cls, "nativeHandle", "J");
    if (field_id == null) {
        log.err("Failed to get nativeHandle field ID for setting", .{});
        return;
    }

    env_vtable.*.SetLongField.?(env, obj, field_id, @bitCast(handle));
}

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

    // Cleanup all renderer states
    if (renderer_map_initialized) {
        var iter = renderer_map.iterator();
        while (iter.next()) |entry| {
            const state = entry.value_ptr.*;
            if (state.renderer) |*renderer| {
                renderer.deinit();
            }
            gpa.allocator().destroy(state);
        }
        renderer_map.deinit();
    }

    // Cleanup global allocator
    _ = gpa.deinit();
}

/// Called when OpenGL surface is created
/// Java signature: void nativeOnSurfaceCreated()
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeOnSurfaceCreated(
    env: *c.JNIEnv,
    obj: c.jobject,
) void {
    var handle = getNativeHandle(env, obj);

    log.info("nativeOnSurfaceCreated - handle={d}, OpenGL context (re)created", .{handle});

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

    // If no handle exists yet, create one
    if (handle == 0) {
        handle = createRendererState() catch |err| {
            log.err("Failed to create renderer state: {}", .{err});
            return;
        };
        setNativeHandle(env, obj, handle);
        log.info("Created new renderer state with handle {d}", .{handle});
    }

    // Get the renderer state for this instance
    const state = getRendererState(handle) orelse {
        log.err("No renderer state found for handle {d}", .{handle});
        return;
    };

    // IMPORTANT: When onSurfaceCreated is called, the OpenGL context has been (re)created.
    // This happens when:
    // - The app first starts
    // - The app returns from background
    // - The OpenGL context is lost for any reason
    //
    // When the context is recreated, all OpenGL objects (shaders, programs, VAOs, textures, buffers)
    // become invalid and must be recreated.

    // Clean up the old renderer if it exists (its OpenGL objects are now invalid)
    if (state.renderer) |*renderer| {
        log.info("Cleaning up old renderer for handle {d} (OpenGL context was recreated)", .{handle});
        renderer.deinit();
        state.renderer = null;
    }

    // Reset initialization state so onSurfaceChanged will recreate the renderer
    state.initialized = false;
    state.surface_sized = false;

    log.info("OpenGL context ready for handle {d}, renderer will be recreated in onSurfaceChanged", .{handle});
}

/// Called when OpenGL surface size changes
/// Java signature: void nativeOnSurfaceChanged(int width, int height, int dpi, int fontSize)
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeOnSurfaceChanged(
    env: *c.JNIEnv,
    obj: c.jobject,
    width: c.jint,
    height: c.jint,
    dpi: c.jint,
    font_size: c.jint,
) void {
    const handle = getNativeHandle(env, obj);

    log.info("nativeOnSurfaceChanged: handle={d}, {d}x{d} at {d} DPI, font size: {d}px", .{ handle, width, height, dpi, font_size });

    if (handle == 0) {
        log.err("No native handle set, call nativeOnSurfaceCreated first", .{});
        return;
    }

    const state = getRendererState(handle) orelse {
        log.err("No renderer state found for handle {d}", .{handle});
        return;
    };

    // Note: glViewport will be set by the renderer to match the expanded projection matrix
    // This ensures viewport and projection dimensions are in sync to avoid GL errors

    // Mark that surface has been sized at least once
    state.surface_sized = true;

    // Store initial font size for potential re-initialization
    const font_size_u32: u32 = if (font_size > 0) @intCast(font_size) else 0;
    if (font_size_u32 > 0) {
        state.initial_font_size = font_size_u32;
    }

    // Initialize renderer on first surface change (now we have real dimensions!)
    if (!state.initialized) {
        log.info("Initializing renderer for handle {d} with dimensions: {d}x{d} at {d} DPI, font size: {d}px", .{ handle, width, height, dpi, font_size });

        const allocator = gpa.allocator();
        state.renderer = Renderer.init(allocator, @intCast(width), @intCast(height), @intCast(dpi), state.initial_font_size) catch |err| {
            log.err("Failed to initialize renderer: {}", .{err});
            return;
        };
        state.initialized = true;
        state.current_font_size = state.initial_font_size; // Track initial font size

        log.info("Renderer initialized successfully for handle {d}", .{handle});
        log.info("Viewport set to {d}x{d}", .{ width, height });
        return; // Don't resize on first init - we just initialized with correct size!
    }

    // Handle font size changes and dimension changes
    if (state.renderer) |*renderer| {
        // Check font size change FIRST - updateFontSize recalculates grid internally
        if (font_size_u32 > 0 and font_size_u32 != state.current_font_size) {
            log.info("Font size changed for handle {d}: {d}px -> {d}px", .{ handle, state.current_font_size, font_size_u32 });
            renderer.updateFontSize(font_size_u32) catch |err| {
                log.err("Failed to update font size: {}", .{err});
                return;
            };
            state.current_font_size = font_size_u32;
            log.info("Font size updated to {d}px, grid recalculated", .{font_size_u32});
            // Font size change also updates the grid, so we're done
            return;
        }

        // Check if dimensions changed (orientation change, etc.)
        const current_size = .{ .width = renderer.width, .height = renderer.height };
        const new_size = .{ .width = @as(u32, @intCast(width)), .height = @as(u32, @intCast(height)) };

        if (current_size.width != new_size.width or current_size.height != new_size.height) {
            log.info("Surface dimensions changed for handle {d}, resizing renderer", .{handle});
            renderer.resize(new_size.width, new_size.height) catch |err| {
                log.err("Failed to resize renderer: {}", .{err});
                return;
            };
            log.info("Renderer resized to {d}x{d}", .{ width, height });
        } else {
            log.debug("Surface dimensions and font size unchanged, skipping update", .{});
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
    const handle = getNativeHandle(env, obj);

    if (handle == 0) {
        return;
    }

    const state = getRendererState(handle) orelse {
        return;
    };

    if (!state.initialized) {
        log.warn("Attempted to draw frame before renderer initialized (handle={d})", .{handle});
        return;
    }

    // Render using the renderer module
    if (state.renderer) |*renderer| {
        renderer.render() catch |err| {
            log.err("Failed to render frame: {}", .{err});
            return;
        };
    } else {
        log.warn("Renderer not initialized (handle={d})", .{handle});
    }
}

/// Called to destroy the renderer
/// Java signature: void nativeDestroy()
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeDestroy(
    env: *c.JNIEnv,
    obj: c.jobject,
) void {
    const handle = getNativeHandle(env, obj);

    log.info("nativeDestroy (handle={d})", .{handle});

    if (handle == 0) {
        return;
    }

    destroyRendererState(handle);
    setNativeHandle(env, obj, 0);

    log.info("Renderer destroyed (handle={d})", .{handle});
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
    const handle = getNativeHandle(env, obj);

    log.info("nativeSetFontSize: {d}px (handle={d})", .{ font_size, handle });

    if (handle == 0) {
        log.warn("No native handle set", .{});
        return;
    }

    const state = getRendererState(handle) orelse {
        log.warn("No renderer state for handle {d}", .{handle});
        return;
    };

    if (!state.initialized) {
        log.warn("Attempted to set font size before renderer initialized", .{});
        return;
    }

    if (state.renderer) |*renderer| {
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
    const handle = getNativeHandle(env, obj);

    log.info("nativeProcessInput called (handle={d})", .{handle});

    if (handle == 0) {
        log.warn("No native handle set", .{});
        return;
    }

    const state = getRendererState(handle) orelse {
        log.warn("No renderer state for handle {d}", .{handle});
        return;
    };

    if (!state.initialized) {
        log.warn("Attempted to process input before renderer initialized", .{});
        return;
    }

    if (state.renderer) |*renderer| {
        // Get the string length first to allocate appropriate buffer
        const env_vtable = env.*.?;
        const str_len = env_vtable.*.GetStringUTFLength.?(env, ansiSequence);
        if (str_len <= 0) {
            log.warn("Empty or invalid input string", .{});
            return;
        }

        const len: usize = @intCast(str_len);
        log.info("Processing {} bytes of ANSI input", .{len});

        // Dynamically allocate buffer (round up to 512KB chunks)
        const chunk_size: usize = 512 * 1024;
        const alloc_size = ((len + chunk_size - 1) / chunk_size) * chunk_size;
        const allocator = gpa.allocator();

        const buffer = allocator.alloc(u8, alloc_size) catch |err| {
            log.err("Failed to allocate buffer of {} bytes: {}", .{ alloc_size, err });
            return;
        };
        defer allocator.free(buffer);

        // Convert JNI string to Zig string using dynamically allocated buffer
        const input_data = jni.getJString(env, ansiSequence, buffer) catch |err| {
            log.err("Failed to get JNI string: {}", .{err});
            return;
        };

        // Feed the input to the terminal manager
        renderer.terminal_manager.processInput(input_data) catch |err| {
            log.err("Failed to process input: {}", .{err});
            return;
        };

        log.info("Input processed successfully: {} bytes", .{input_data.len});
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
    const handle = getNativeHandle(env, obj);

    if (handle == 0) {
        return 0;
    }

    const state = getRendererState(handle) orelse {
        return 0;
    };

    if (!state.initialized) {
        log.warn("Attempted to get scrollback rows before renderer initialized", .{});
        return 0;
    }

    if (state.renderer) |*renderer| {
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
    const handle = getNativeHandle(env, obj);

    if (handle == 0) {
        return 20.0;
    }

    const state = getRendererState(handle) orelse {
        return 20.0;
    };

    if (!state.initialized) {
        log.warn("Attempted to get font line spacing before renderer initialized", .{});
        return 20.0; // Default fallback
    }

    if (state.renderer) |*renderer| {
        return renderer.getFontLineSpacing();
    }

    return 20.0; // Default fallback
}

/// Get the content height in pixels (actual rendered content, not full grid)
/// Java signature: float nativeGetContentHeight()
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeGetContentHeight(
    env: *c.JNIEnv,
    obj: c.jobject,
) c.jfloat {
    const handle = getNativeHandle(env, obj);

    if (handle == 0) {
        return 0.0;
    }

    const state = getRendererState(handle) orelse {
        return 0.0;
    };

    if (!state.initialized) {
        log.warn("Attempted to get content height before renderer initialized", .{});
        return 0.0;
    }

    if (state.renderer) |*renderer| {
        return renderer.getContentHeight();
    }

    return 0.0;
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
    const handle = getNativeHandle(env, obj);

    if (handle == 0) {
        return;
    }

    const state = getRendererState(handle) orelse {
        return;
    };

    if (!state.initialized) {
        log.warn("Attempted to scroll before renderer initialized", .{});
        return;
    }

    if (state.renderer) |*renderer| {
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
    const handle = getNativeHandle(env, obj);

    if (handle == 0) {
        return c.JNI_TRUE;
    }

    const state = getRendererState(handle) orelse {
        return c.JNI_TRUE;
    };

    if (!state.initialized) {
        return c.JNI_TRUE; // Default to bottom when not initialized
    }

    if (state.renderer) |*renderer| {
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
    const handle = getNativeHandle(env, obj);

    if (handle == 0) {
        return 0;
    }

    const state = getRendererState(handle) orelse {
        return 0;
    };

    if (!state.initialized) {
        return 0;
    }

    if (state.renderer) |*renderer| {
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
    const handle = getNativeHandle(env, obj);

    if (handle == 0) {
        return;
    }

    const state = getRendererState(handle) orelse {
        return;
    };

    if (!state.initialized) {
        log.warn("Attempted to scroll to bottom before renderer initialized", .{});
        return;
    }

    if (state.renderer) |*renderer| {
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
    const handle = getNativeHandle(env, obj);

    if (handle == 0) {
        return;
    }

    const state = getRendererState(handle) orelse {
        return;
    };

    if (!state.initialized) {
        return;
    }

    if (state.renderer) |*renderer| {
        renderer.setScrollPixelOffset(offset);
    }
}

/// Enable or disable FPS display overlay
/// Java signature: void nativeSetShowFps(boolean show)
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeSetShowFps(
    env: *c.JNIEnv,
    obj: c.jobject,
    show: c.jboolean,
) void {
    const handle = getNativeHandle(env, obj);

    if (handle == 0) {
        return;
    }

    const state = getRendererState(handle) orelse {
        return;
    };

    if (!state.initialized) {
        log.warn("Attempted to set show FPS before renderer initialized", .{});
        return;
    }

    if (state.renderer) |*renderer| {
        renderer.setShowFps(show == c.JNI_TRUE);
    }
}

/// Get the current terminal grid size (columns and rows)
/// Java signature: int[] nativeGetGridSize()
/// Returns [cols, rows] array
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeGetGridSize(
    env: *c.JNIEnv,
    obj: c.jobject,
) c.jintArray {
    const handle = getNativeHandle(env, obj);
    const env_vtable = env.*.?;

    // Create a new int array of size 2
    const result = env_vtable.*.NewIntArray.?(env, 2);
    if (result == null) {
        log.err("Failed to create jintArray for grid size", .{});
        return null;
    }

    var grid_size: [2]c.jint = .{ 0, 0 };

    if (handle == 0) {
        env_vtable.*.SetIntArrayRegion.?(env, result, 0, 2, &grid_size);
        return result;
    }

    const state = getRendererState(handle) orelse {
        env_vtable.*.SetIntArrayRegion.?(env, result, 0, 2, &grid_size);
        return result;
    };

    if (!state.initialized) {
        log.warn("Attempted to get grid size before renderer initialized", .{});
    } else if (state.renderer) |*renderer| {
        grid_size[0] = @intCast(renderer.grid_cols);
        grid_size[1] = @intCast(renderer.grid_rows);
    }

    // Set the array elements
    env_vtable.*.SetIntArrayRegion.?(env, result, 0, 2, &grid_size);

    return result;
}

// ============================================================================
// Selection JNI Methods
// ============================================================================

/// Get the cell size for coordinate conversion
/// Java signature: float[] nativeGetCellSize()
/// Returns [cellWidth, cellHeight] array
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeGetCellSize(
    env: *c.JNIEnv,
    obj: c.jobject,
) c.jfloatArray {
    const handle = getNativeHandle(env, obj);
    const env_vtable = env.*.?;

    // Create a new float array of size 2
    const result = env_vtable.*.NewFloatArray.?(env, 2);
    if (result == null) {
        log.err("Failed to create jfloatArray for cell size", .{});
        return null;
    }

    var cell_size: [2]c.jfloat = .{ 0.0, 0.0 };

    if (handle != 0) {
        if (getRendererState(handle)) |state| {
            if (state.initialized) {
                if (state.renderer) |*renderer| {
                    cell_size[0] = renderer.uniforms.cell_size[0];
                    cell_size[1] = renderer.uniforms.cell_size[1];
                }
            }
        }
    }

    env_vtable.*.SetFloatArrayRegion.?(env, result, 0, 2, &cell_size);
    return result;
}

/// Start a new selection at the given cell coordinates
/// Java signature: void nativeStartSelection(int col, int row)
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeStartSelection(
    env: *c.JNIEnv,
    obj: c.jobject,
    col: c.jint,
    row: c.jint,
) void {
    const handle = getNativeHandle(env, obj);

    if (handle == 0) {
        return;
    }

    const state = getRendererState(handle) orelse {
        return;
    };

    if (!state.initialized) {
        log.warn("Attempted to start selection before renderer initialized", .{});
        return;
    }

    if (state.renderer) |*renderer| {
        renderer.terminal_manager.startSelection(@intCast(col), @intCast(row)) catch |err| {
            log.err("Failed to start selection: {}", .{err});
        };
    }
}

/// Update the end point of the current selection
/// Java signature: void nativeUpdateSelection(int col, int row)
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeUpdateSelection(
    env: *c.JNIEnv,
    obj: c.jobject,
    col: c.jint,
    row: c.jint,
) void {
    const handle = getNativeHandle(env, obj);

    if (handle == 0) {
        return;
    }

    const state = getRendererState(handle) orelse {
        return;
    };

    if (!state.initialized) {
        return;
    }

    if (state.renderer) |*renderer| {
        renderer.terminal_manager.updateSelection(@intCast(col), @intCast(row)) catch |err| {
            log.err("Failed to update selection: {}", .{err});
        };
    }
}

/// Clear the current selection
/// Java signature: void nativeClearSelection()
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeClearSelection(
    env: *c.JNIEnv,
    obj: c.jobject,
) void {
    const handle = getNativeHandle(env, obj);

    if (handle == 0) {
        return;
    }

    const state = getRendererState(handle) orelse {
        return;
    };

    if (!state.initialized) {
        return;
    }

    if (state.renderer) |*renderer| {
        renderer.terminal_manager.clearSelection();
    }
}

/// Check if there is an active selection
/// Java signature: boolean nativeHasSelection()
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeHasSelection(
    env: *c.JNIEnv,
    obj: c.jobject,
) c.jboolean {
    const handle = getNativeHandle(env, obj);

    if (handle == 0) {
        return c.JNI_FALSE;
    }

    const state = getRendererState(handle) orelse {
        return c.JNI_FALSE;
    };

    if (!state.initialized) {
        return c.JNI_FALSE;
    }

    if (state.renderer) |*renderer| {
        return if (renderer.terminal_manager.hasSelection()) c.JNI_TRUE else c.JNI_FALSE;
    }

    return c.JNI_FALSE;
}

/// Get the selected text
/// Java signature: String nativeGetSelectionText()
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeGetSelectionText(
    env: *c.JNIEnv,
    obj: c.jobject,
) c.jstring {
    const handle = getNativeHandle(env, obj);

    if (handle == 0) {
        return null;
    }

    const state = getRendererState(handle) orelse {
        return null;
    };

    if (!state.initialized) {
        return null;
    }

    if (state.renderer) |*renderer| {
        const text = renderer.terminal_manager.getSelectionText() catch |err| {
            log.err("Failed to get selection text: {}", .{err});
            return null;
        };

        if (text) |txt| {
            defer gpa.allocator().free(txt);
            return jni.newJString(env, txt) catch |err| {
                log.err("Failed to create JNI string for selection text: {}", .{err});
                return null;
            };
        }
    }

    return null;
}

/// Get the selection bounds in viewport coordinates
/// Java signature: int[] nativeGetSelectionBounds()
/// Returns [startCol, startRow, endCol, endRow] or null if no selection
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeGetSelectionBounds(
    env: *c.JNIEnv,
    obj: c.jobject,
) c.jintArray {
    const handle = getNativeHandle(env, obj);
    const env_vtable = env.*.?;

    if (handle == 0) {
        return null;
    }

    const state = getRendererState(handle) orelse {
        return null;
    };

    if (!state.initialized) {
        return null;
    }

    if (state.renderer) |*renderer| {
        const bounds = renderer.terminal_manager.getSelectionBounds() orelse {
            return null;
        };

        // Create a new int array of size 4
        const result = env_vtable.*.NewIntArray.?(env, 4);
        if (result == null) {
            log.err("Failed to create jintArray for selection bounds", .{});
            return null;
        }

        var bounds_array: [4]c.jint = .{
            @intCast(bounds.start_col),
            @intCast(bounds.start_row),
            @intCast(bounds.end_col),
            @intCast(bounds.end_row),
        };

        env_vtable.*.SetIntArrayRegion.?(env, result, 0, 4, &bounds_array);
        return result;
    }

    return null;
}

// ============================================================================
// Hyperlink JNI Methods
// ============================================================================

/// Get the hyperlink URI at the given cell coordinates
/// Java signature: String nativeGetHyperlinkAtCell(int col, int row)
/// Returns the URI string or null if no hyperlink
export fn Java_com_ghostty_android_renderer_GhosttyRenderer_nativeGetHyperlinkAtCell(
    env: *c.JNIEnv,
    obj: c.jobject,
    col: c.jint,
    row: c.jint,
) c.jstring {
    const handle = getNativeHandle(env, obj);

    if (handle == 0) {
        return null;
    }

    const state = getRendererState(handle) orelse {
        return null;
    };

    if (!state.initialized) {
        return null;
    }

    if (state.renderer) |*renderer| {
        const uri = renderer.terminal_manager.getHyperlinkAtCell(@intCast(col), @intCast(row)) catch |err| {
            log.err("Failed to get hyperlink: {}", .{err});
            return null;
        };

        if (uri) |u| {
            defer gpa.allocator().free(u);
            return jni.newJString(env, u) catch |err| {
                log.err("Failed to create JNI string for hyperlink URI: {}", .{err});
                return null;
            };
        }
    }

    return null;
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
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeGetContentHeight;
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeScrollDelta;
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeIsViewportAtBottom;
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeGetViewportOffset;
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeScrollToBottom;
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeSetScrollPixelOffset;
    // FPS display
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeSetShowFps;
    // Grid size
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeGetGridSize;
    // Selection methods
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeGetCellSize;
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeStartSelection;
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeUpdateSelection;
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeClearSelection;
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeHasSelection;
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeGetSelectionText;
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeGetSelectionBounds;
    // Hyperlink methods
    _ = Java_com_ghostty_android_renderer_GhosttyRenderer_nativeGetHyperlinkAtCell;
}
