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

/// Initialize a new terminal with the specified size
pub fn init(allocator: Allocator, cols: u16, rows: u16) !TerminalManager {
    log.info("Initializing terminal: {}x{}", .{ cols, rows });

    const terminal = try ghostty_vt.Terminal.init(allocator, .{
        .cols = @intCast(cols),
        .rows = @intCast(rows),
    });

    return .{
        .allocator = allocator,
        .terminal = terminal,
    };
}

/// Clean up terminal resources
pub fn deinit(self: *TerminalManager) void {
    log.info("Deinitializing terminal", .{});
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
    log.info("Resizing terminal: {}x{}", .{ cols, rows });
    try self.terminal.resize(
        self.allocator,
        @intCast(cols),
        @intCast(rows),
    );
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
