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

/// Saved viewport anchor for scroll restoration across resize.
/// This Pin tracks the content at the top-left of the viewport,
/// allowing us to restore the scroll position after terminal resize/reflow.
saved_viewport_anchor: ?ghostty_vt.PageList.Pin = null,

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

/// Scroll viewport to an absolute row offset
/// Row 0 is the top of scrollback, and increases towards the active area
/// Use getViewportOffset() to get the current offset for later restoration
pub fn scrollToViewportOffset(self: *TerminalManager, row: usize) void {
    const screen = self.terminal.screens.get(.primary).?;
    screen.pages.scroll(.{ .row = row });
    log.debug("Scrolled viewport to row {}", .{row});
}

// =============================================================================
// Viewport Anchor API (for scroll preservation across resize)
// =============================================================================

/// Save the current viewport anchor (top-left cell) for later restoration.
/// Call this BEFORE resize operations to preserve scroll position.
/// If the viewport is at the bottom, no anchor is saved (we want to stay at bottom).
pub fn saveViewportAnchor(self: *TerminalManager) void {
    // If at bottom, don't save (we want to stay at bottom for new output)
    if (self.isViewportAtBottom()) {
        self.saved_viewport_anchor = null;
        log.debug("saveViewportAnchor: at bottom, not saving", .{});
        return;
    }

    const screen = self.terminal.screens.get(.primary).?;
    const pt = point.Point{ .viewport = .{ .x = 0, .y = 0 } };

    if (screen.pages.pin(pt)) |pin| {
        self.saved_viewport_anchor = pin;
        log.debug("saveViewportAnchor: saved pin for viewport top-left", .{});
    } else {
        self.saved_viewport_anchor = null;
        log.warn("saveViewportAnchor: failed to get pin for (0,0)", .{});
    }
}

/// Restore the viewport to show the previously saved anchor.
/// Call this AFTER resize operations to restore scroll position.
/// The saved anchor is cleared after restoration.
pub fn restoreViewportAnchor(self: *TerminalManager) void {
    const anchor = self.saved_viewport_anchor orelse {
        log.debug("restoreViewportAnchor: no saved anchor, staying at current position", .{});
        return;
    };

    // Clear saved anchor
    self.saved_viewport_anchor = null;

    var screen = self.terminal.screens.get(.primary).?;

    // Convert Pin to screen coordinates (absolute row from top of buffer)
    const screen_pt = screen.pages.pointFromPin(.screen, anchor) orelse {
        log.warn("restoreViewportAnchor: pin no longer valid after resize", .{});
        return;
    };

    // Scroll so this row is at the top of the viewport
    const row = screen_pt.screen.y;
    screen.pages.scroll(.{ .row = row });
    log.debug("restoreViewportAnchor: scrolled to row {}", .{row});
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

/// Check if synchronized output mode is active (mode 2026).
/// When active, the terminal is buffering changes and rendering should be deferred
/// until the mode is disabled (ESC[?2026l).
pub fn isSynchronizedOutputActive(self: *TerminalManager) bool {
    return self.terminal.modes.get(.synchronized_output);
}

// =============================================================================
// Selection API
// =============================================================================

const Selection = ghostty_vt.Selection;
const point = ghostty_vt.point;

/// Selection bounds in viewport coordinates
pub const SelectionBounds = struct {
    start_col: u16,
    start_row: u16,
    end_col: u16,
    end_row: u16,
};

/// Start a new selection at the given viewport coordinates.
/// This creates an initial selection with start and end at the same point.
pub fn startSelection(self: *TerminalManager, col: u16, row: u16) !void {
    var screen = self.terminal.screens.get(.primary).?;

    // Convert viewport coordinates to a Pin
    const pt = point.Point{ .viewport = .{ .x = col, .y = row } };
    const pin = screen.pages.pin(pt) orelse {
        log.warn("startSelection: invalid coordinates ({}, {})", .{ col, row });
        return;
    };

    // Create selection with same start and end point
    const sel = Selection.init(pin, pin, false);
    try screen.select(sel);

    log.debug("Started selection at ({}, {})", .{ col, row });
}

/// Update the end point of the current selection.
/// If no selection exists, this is a no-op.
pub fn updateSelection(self: *TerminalManager, col: u16, row: u16) !void {
    var screen = self.terminal.screens.get(.primary).?;

    // Get current selection
    var sel = screen.selection orelse return;

    // Convert viewport coordinates to a Pin
    const pt = point.Point{ .viewport = .{ .x = col, .y = row } };
    const pin = screen.pages.pin(pt) orelse {
        log.warn("updateSelection: invalid coordinates ({}, {})", .{ col, row });
        return;
    };

    // Update the end point
    sel.endPtr().* = pin;
    screen.dirty.selection = true;

    log.debug("Updated selection end to ({}, {})", .{ col, row });
}

/// Clear the current selection.
pub fn clearSelection(self: *TerminalManager) void {
    var screen = self.terminal.screens.get(.primary).?;
    screen.clearSelection();
    log.debug("Cleared selection", .{});
}

/// Check if there is an active selection.
pub fn hasSelection(self: *TerminalManager) bool {
    const screen = self.terminal.screens.get(.primary).?;
    return screen.selection != null;
}

/// Get the selected text as a string.
/// Returns null if no selection exists.
/// Caller owns the returned memory and must free it with the allocator.
pub fn getSelectionText(self: *TerminalManager) !?[:0]const u8 {
    var screen = self.terminal.screens.get(.primary).?;

    const sel = screen.selection orelse return null;

    return try screen.selectionString(self.allocator, .{
        .sel = sel,
        .trim = true,
    });
}

/// Get the selection bounds in viewport coordinates.
/// Returns null if no selection exists.
pub fn getSelectionBounds(self: *TerminalManager) ?SelectionBounds {
    var screen = self.terminal.screens.get(.primary).?;

    const sel = screen.selection orelse return null;

    // Get ordered bounds (top-left and bottom-right)
    const tl = sel.topLeft(screen);
    const br = sel.bottomRight(screen);

    // Convert pins to viewport coordinates
    const tl_pt = screen.pages.pointFromPin(.viewport, tl) orelse return null;
    const br_pt = screen.pages.pointFromPin(.viewport, br) orelse return null;

    return .{
        .start_col = tl.x,
        .start_row = @intCast(tl_pt.coord().y),
        .end_col = br.x,
        .end_row = @intCast(br_pt.coord().y),
    };
}

// =============================================================================
// Hyperlink API
// =============================================================================

/// Get the hyperlink URI at the given viewport coordinates.
/// Returns null if no hyperlink exists at the given position.
/// Caller owns the returned memory and must free it with the allocator.
pub fn getHyperlinkAtCell(self: *TerminalManager, col: u16, row: u16) !?[]const u8 {
    // Update render state to ensure it's current
    try self.updateRenderState();

    // Check if we have row data
    const row_slice = self.render_state.row_data.slice();
    const row_pins = row_slice.items(.pin);

    if (row >= row_pins.len) {
        log.debug("getHyperlinkAtCell: row {} out of range (max {})", .{ row, row_pins.len });
        return null;
    }

    // Get the page for this row
    const page_ptr = &row_pins[row].node.data;

    // Get the row and cell at the position
    const rac = page_ptr.getRowAndCell(col, row);

    // Check if the cell has a hyperlink
    if (!rac.cell.hyperlink) {
        return null;
    }

    // Look up the hyperlink ID
    const link_id = page_ptr.lookupHyperlink(rac.cell) orelse {
        log.warn("getHyperlinkAtCell: cell has hyperlink flag but no ID", .{});
        return null;
    };

    // Get the hyperlink entry from the set
    const link = page_ptr.hyperlink_set.get(page_ptr.memory, link_id);

    // Extract the URI string
    const uri = link.uri.slice(page_ptr.memory);

    // Duplicate the URI string so caller owns it
    const result = try self.allocator.dupe(u8, uri);
    log.debug("Found hyperlink at ({}, {}): {s}", .{ col, row, result });

    return result;
}
