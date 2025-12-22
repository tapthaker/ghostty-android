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
const codepoint_width = @import("codepoint_width.zig");

const log = std.log.scoped(.screen_extractor);

/// Extracted cell data ready for rendering
pub const CellData = struct {
    /// Primary Unicode codepoint to render
    codepoint: u21,

    /// Additional codepoints if this is a grapheme cluster
    /// (e.g., base character + combining marks)
    grapheme_cluster: ?[]const u21 = null,

    /// Character width (0=zero-width, 1=single, 2=double)
    width: u8 = 1,

    /// Is this a continuation cell for a wide character?
    is_wide_continuation: bool = false,

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

    const screen = terminal.screens.get(.primary).?;
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
            // Pin to the viewport coordinates (tests write to viewport)
            const pin = screen.pages.pin(.{ .viewport = .{
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

            // Handle spacer cells for wide characters
            // Check if this is a spacer cell (continuation of wide char)
            if (cell.wide == .spacer_tail or cell.wide == .spacer_head) {
                // This is a spacer cell for a wide character
                // Skip it but still account for the cell position
                continue;
            }

            // Get the codepoint and check for grapheme clusters
            const grapheme_codepoints: ?[]const u21 = null;

            const primary_codepoint: u21 = switch (cell.content_tag) {
                .codepoint => cell.content.codepoint,
                .codepoint_grapheme => blk: {
                    // This cell contains a grapheme cluster
                    // TODO: Extract additional codepoints from grapheme storage
                    // For now, we'll just use the base codepoint
                    // In a full implementation, we'd access the grapheme storage
                    // from the page to get all codepoints in the cluster
                    break :blk cell.content.codepoint;
                },
                .bg_color_palette, .bg_color_rgb => ' ', // Color-only cells render as space
            };

            // Get the character width
            const char_width = codepoint_width.codepointWidth(primary_codepoint);

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
                .codepoint = primary_codepoint,
                .grapheme_cluster = grapheme_codepoints,
                .width = char_width,
                .is_wide_continuation = false,
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
