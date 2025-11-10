//! Screen Extractor - extracts cell data from VT terminal screen
//!
//! Iterates through the terminal screen grid and extracts:
//! - Character codepoints
//! - Foreground colors (RGB)
//! - Background colors (RGB)
//! - Cell positions (row, col)

const std = @import("std");
const Allocator = std.mem.Allocator;
const ghostty_vt = @import("ghostty-vt");

const log = std.log.scoped(.screen_extractor);

/// Extracted cell data ready for rendering
pub const CellData = struct {
    /// Unicode codepoint to render
    codepoint: u21,

    /// Foreground color (RGBA)
    fg_color: [4]u8,

    /// Background color (RGBA), or [0,0,0,0] for default
    bg_color: [4]u8,

    /// Cell column position
    col: u16,

    /// Cell row position
    row: u16,

    /// Text style attributes
    bold: bool = false,
    italic: bool = false,
    dim: bool = false, // called 'faint' in VT
    strikethrough: bool = false,
    underline: Underline = .none,
    inverse: bool = false,

    pub const Underline = enum(u3) {
        none = 0,
        single = 1,
        double = 2,
        curly = 3,
        dotted = 4,
        dashed = 5,
    };
};

/// Extract all visible cells from the terminal screen
pub fn extractCells(
    allocator: Allocator,
    terminal: *ghostty_vt.Terminal,
) ![]CellData {
    const cols: usize = @intCast(terminal.cols);
    const rows: usize = @intCast(terminal.rows);
    const total_cells = cols * rows;

    log.debug("Extracting {} cells ({}x{})", .{ total_cells, cols, rows });

    var cells = try std.ArrayList(CellData).initCapacity(allocator, total_cells);
    errdefer cells.deinit(allocator);

    const screen = &terminal.screen;
    const palette = &terminal.colors.palette.current;

    // Default colors
    const default_fg: ghostty_vt.color.RGB = terminal.colors.foreground.get() orelse .{
        .r = 255,
        .g = 255,
        .b = 255,
    };
    const default_bg: ?ghostty_vt.color.RGB = terminal.colors.background.get();

    var row: usize = 0;
    while (row < rows) : (row += 1) {
        var col: usize = 0;
        while (col < cols) : (col += 1) {
            // Pin to the active screen coordinates
            const pin = screen.pages.pin(.{ .active = .{
                .x = @intCast(col),
                .y = @intCast(row),
            } }) orelse {
                log.err("Failed to pin cell at ({}, {})", .{ row, col });
                continue;
            };

            const cell = pin.rowAndCell().cell;

            // Get the style for this cell
            const page = pin.node.data;
            const style_val = page.styles.get(page.memory, cell.style_id);

            // Extract foreground color
            const fg_rgb = style_val.fg(.{
                .default = default_fg,
                .palette = palette,
            });

            // Extract background color
            const bg_rgb_opt = style_val.bg(cell, palette);
            const bg_rgb = bg_rgb_opt orelse default_bg orelse ghostty_vt.color.RGB{
                .r = 0,
                .g = 0,
                .b = 0,
            };

            // Get the codepoint - handle spacer head cells
            const codepoint: u21 = switch (cell.content_tag) {
                .codepoint => cell.content.codepoint,
                .codepoint_grapheme => cell.content.codepoint,
                .bg_color_palette, .bg_color_rgb => ' ', // Color-only cells render as space
            };

            // Extract text style attributes from VT style flags
            const underline_type: CellData.Underline = switch (style_val.flags.underline) {
                .none => .none,
                .single => .single,
                .double => .double,
                .curly => .curly,
                .dotted => .dotted,
                .dashed => .dashed,
            };

            try cells.append(allocator, .{
                .codepoint = codepoint,
                .fg_color = .{ fg_rgb.r, fg_rgb.g, fg_rgb.b, 255 },
                .bg_color = .{ bg_rgb.r, bg_rgb.g, bg_rgb.b, 255 },
                .col = @intCast(col),
                .row = @intCast(row),
                .bold = style_val.flags.bold,
                .italic = style_val.flags.italic,
                .dim = style_val.flags.faint,
                .strikethrough = style_val.flags.strikethrough,
                .underline = underline_type,
                .inverse = style_val.flags.inverse,
            });
        }
    }

    log.debug("Extracted {} cells successfully", .{cells.items.len});
    return cells.toOwnedSlice(allocator);
}

/// Free cell data array
pub fn freeCells(allocator: Allocator, cells: []CellData) void {
    allocator.free(cells);
}
