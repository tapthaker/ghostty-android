//! Terminal Manager - wraps libghostty-vt Terminal for Android integration
//!
//! This provides a simple interface for:
//! - Creating and destroying VT terminal instances
//! - Processing ANSI escape sequences
//! - Extracting screen state for rendering

const std = @import("std");
const Allocator = std.mem.Allocator;
const ghostty_vt = @import("ghostty-vt");

const log = std.log.scoped(.terminal_manager);

/// Terminal Manager manages a VT terminal instance
pub const TerminalManager = @This();

allocator: Allocator,
terminal: ghostty_vt.Terminal,
render_state: ghostty_vt.RenderState = .empty,

/// Initialize a new terminal with the specified size
pub fn init(allocator: Allocator, cols: u16, rows: u16) !TerminalManager {
    log.info("Initializing terminal: {}x{}", .{ cols, rows });

    const terminal = try ghostty_vt.Terminal.init(allocator, .{
        .cols = @intCast(cols),
        .rows = @intCast(rows),
        .default_modes = .{
            .linefeed = true, // LNM mode: make \n act as \r\n (newline with carriage return)
            .wraparound = true, // Enable text reflow when terminal is resized
            .grapheme_cluster = true, // Enable proper grapheme width handling (mode 2027)
        },
    });

    // Verify modes were set correctly
    const wraparound_enabled = terminal.modes.get(.wraparound);
    const linefeed_enabled = terminal.modes.get(.linefeed);
    log.info("Terminal initialized with modes: wraparound={}, linefeed={}", .{
        wraparound_enabled, linefeed_enabled
    });

    return .{
        .allocator = allocator,
        .terminal = terminal,
    };
}

/// Clean up terminal resources
pub fn deinit(self: *TerminalManager) void {
    log.info("Deinitializing terminal", .{});
    self.render_state.deinit(self.allocator);
    self.terminal.deinit(self.allocator);
}

/// Process a slice of VT input (raw bytes including ANSI sequences)
pub fn processInput(self: *TerminalManager, data: []const u8) !void {
    var stream = self.terminal.vtStream();
    defer stream.deinit();

    try stream.nextSlice(data);
    log.debug("Processed {} bytes of input", .{data.len});
}

/// Resize the terminal
pub fn resize(self: *TerminalManager, cols: u16, rows: u16) !void {
    log.info("Resizing terminal: {}x{} -> {}x{}", .{
        self.terminal.cols, self.terminal.rows, cols, rows
    });

    // Log current mode states
    const wraparound_enabled = self.terminal.modes.get(.wraparound);
    log.info("Terminal modes: wraparound={}", .{wraparound_enabled});

    // Get some terminal content before resize for debugging
    const screen = self.terminal.screens.get(.primary).?;
    const cursor_before = screen.cursor;
    log.info("Before resize: cursor at ({}, {}), pending_wrap={}", .{
        cursor_before.x, cursor_before.y, cursor_before.pending_wrap
    });

    // Perform the resize
    try self.terminal.resize(
        self.allocator,
        @intCast(cols),
        @intCast(rows),
    );

    // Check state after resize
    const cursor_after = self.terminal.screens.get(.primary).?.cursor;
    log.info("After resize: cursor at ({}, {}), pending_wrap={}", .{
        cursor_after.x, cursor_after.y, cursor_after.pending_wrap
    });

    log.info("Terminal resize complete: now {}x{}", .{
        self.terminal.cols, self.terminal.rows
    });
}

/// Get terminal dimensions
pub fn getSize(self: *const TerminalManager) struct { cols: u16, rows: u16 } {
    return .{
        .cols = @intCast(self.terminal.cols),
        .rows = @intCast(self.terminal.rows),
    };
}

/// Get a reference to the underlying terminal for screen extraction
pub fn getTerminal(self: *TerminalManager) *ghostty_vt.Terminal {
    return &self.terminal;
}

/// Get the number of scrollback rows available (rows above the active area)
pub fn getScrollbackRows(self: *TerminalManager) usize {
    const screen = self.terminal.screens.get(.primary).?;
    // total_rows includes both scrollback and active area
    // scrollback = total_rows - active_rows
    const total = screen.pages.total_rows;
    const active = screen.pages.rows;
    if (total > active) {
        return total - active;
    }
    return 0;
}

/// Scroll the viewport by a delta number of rows
/// Positive delta scrolls down (towards newer content/active area)
/// Negative delta scrolls up (towards older content/scrollback)
pub fn scrollDelta(self: *TerminalManager, delta: i32) void {
    const screen = self.terminal.screens.get(.primary).?;
    screen.pages.scroll(.{ .delta_row = delta });
    log.debug("Scrolled viewport by {} rows", .{delta});
}

/// Check if viewport is at the bottom (following active area)
pub fn isViewportAtBottom(self: *TerminalManager) bool {
    const screen = self.terminal.screens.get(.primary).?;
    return screen.viewportIsBottom();
}

/// Get the current scroll offset from the top (0 = at top of scrollback)
pub fn getViewportOffset(self: *TerminalManager) usize {
    var screen = self.terminal.screens.get(.primary).?;
    const scrollbar = screen.pages.scrollbar();
    return scrollbar.offset;
}

/// Scroll viewport to the bottom (active area)
pub fn scrollToBottom(self: *TerminalManager) void {
    const screen = self.terminal.screens.get(.primary).?;
    screen.pages.scroll(.active);
    log.debug("Scrolled viewport to bottom (active area)", .{});
}

/// Update render state from terminal - call before extracting cursor style
pub fn updateRenderState(self: *TerminalManager) !void {
    try self.render_state.update(self.allocator, &self.terminal);
}

/// Get cursor style for rendering using the proper helper
/// Returns null if cursor should be hidden (visibility disabled, blink off, etc.)
pub fn getCursorStyle(
    self: *const TerminalManager,
    opts: ghostty_vt.RendererCursorStyleOptions,
) ?ghostty_vt.RendererCursorStyle {
    return ghostty_vt.rendererCursorStyle(&self.render_state, opts);
}

/// Get cursor viewport position from render state
/// Returns null if cursor is not visible in the current viewport (e.g., scrolled off)
pub fn getCursorViewport(self: *const TerminalManager) ?CursorViewport {
    const vp = self.render_state.cursor.viewport orelse return null;
    return .{
        .x = vp.x,
        .y = vp.y,
        .wide_tail = vp.wide_tail,
    };
}

pub const CursorViewport = struct {
    x: u16,
    y: u16,
    wide_tail: bool,
};

/// Get the number of content rows (cursor Y position + 1)
/// This represents the rows that actually have content rendered
pub fn getContentRows(self: *TerminalManager) usize {
    const screen = self.terminal.screens.get(.primary).?;
    // cursor.y is 0-indexed, so add 1 for total rows with content
    return @as(usize, screen.cursor.y) + 1;
}
