//! Standardized font metrics system for Ghostty Android
//!
//! This module provides proper font size handling using points as the standard
//! unit, with DPI-aware conversion to pixels and accurate metrics extraction.

const std = @import("std");
const freetype = @import("freetype");
const log = std.log.scoped(.font_metrics);

/// Standard font size representation in points with DPI conversion
pub const FontSize = struct {
    /// Font size in points (standard typographic unit)
    /// Common sizes: 10pt, 12pt, 14pt, 16pt, 18pt
    points: f32,

    /// Screen DPI (dots per inch)
    /// Android common values:
    /// - ldpi: 120
    /// - mdpi: 160 (baseline)
    /// - hdpi: 240
    /// - xhdpi: 320
    /// - xxhdpi: 480
    /// - xxxhdpi: 640
    dpi: u16,

    /// Convert points to pixels for rendering
    pub fn toPixels(self: FontSize) f32 {
        // Standard formula: 1 point = 1/72 inch
        // pixels = points × (DPI / 72)
        return (self.points * @as(f32, @floatFromInt(self.dpi))) / 72.0;
    }

    /// Convert points to FreeType 26.6 fixed-point format
    pub fn to26Dot6(self: FontSize) i32 {
        // FreeType uses 26.6 format: 26 bits integer, 6 bits fractional
        // Multiply by 64 (2^6) to convert
        return @intFromFloat(@round(self.points * 64.0));
    }

    /// Create from Android screen density
    pub fn fromAndroidDensity(points: f32, density_dpi: u16) FontSize {
        return .{
            .points = points,
            .dpi = density_dpi,
        };
    }

    /// Create from pixel size (reverse conversion)
    pub fn fromPixels(pixels: f32, dpi: u16) FontSize {
        // pixels = points × (DPI / 72)
        // points = pixels × (72 / DPI)
        const points = (pixels * 72.0) / @as(f32, @floatFromInt(dpi));
        return .{
            .points = points,
            .dpi = dpi,
        };
    }

    /// Get default font size for terminal
    pub fn default(dpi: u16) FontSize {
        return .{
            .points = 10.0, // 10pt default - balanced for mobile screens with high DPI
            .dpi = dpi,
        };
    }
};

/// Extracted font metrics for accurate layout calculations
pub const FontMetrics = struct {
    /// Height above baseline (positive)
    ascent: f32,

    /// Depth below baseline (typically negative)
    descent: f32,

    /// Additional spacing between lines
    line_gap: f32,

    /// Height of capital letters
    cap_height: f32,

    /// Height of lowercase 'x'
    x_height: f32,

    /// Average character width (for monospace fonts)
    average_width: f32,

    /// Maximum character width
    max_width: f32,

    /// Underline position (distance below baseline)
    underline_position: f32,

    /// Underline thickness
    underline_thickness: f32,

    /// Calculate proper cell height using typographic line height
    pub fn cellHeight(self: FontMetrics) u32 {
        // Standard typographic line height calculation
        const line_height = self.ascent - self.descent + self.line_gap;
        const result = @as(u32, @intFromFloat(@ceil(line_height)));
        log.debug("Cell height calculation: ascent={d:.2} - descent={d:.2} + gap={d:.2} = {d:.2} -> {d}", .{
            self.ascent, self.descent, self.line_gap, line_height, result
        });
        return result;
    }

    /// Calculate cell width for monospace fonts
    pub fn cellWidth(self: FontMetrics) u32 {
        // For monospace fonts, use the maximum width
        // This ensures all characters fit properly
        const result = @as(u32, @intFromFloat(@ceil(self.max_width)));
        log.debug("Cell width calculation: max_width={d:.2} -> {d}", .{
            self.max_width, result
        });
        return result;
    }

    /// Calculate baseline position within cell
    pub fn baseline(self: FontMetrics) u32 {
        // Position baseline with half line gap distributed above and below
        const half_gap = self.line_gap / 2.0;
        return @intFromFloat(@ceil(self.ascent + half_gap));
    }

    /// Calculate strikethrough position (middle of x-height)
    pub fn strikethroughPosition(self: FontMetrics) u32 {
        // Strikethrough typically goes through the middle of lowercase letters
        return @intFromFloat(@ceil(self.x_height / 2.0));
    }

    /// Get all line decoration positions
    pub fn getDecorationPositions(self: FontMetrics) struct {
        underline: i32,
        underline_thickness: u32,
        strikethrough: i32,
        strikethrough_thickness: u32,
        overline: i32,
        overline_thickness: u32,
    } {
        const baseline_pos = self.baseline();

        // Underline: use font's underline position or fallback
        const underline_pos = if (self.underline_position != 0)
            @as(i32, @intFromFloat(@round(self.underline_position)))
        else
            @as(i32, @intCast(baseline_pos)) + 2; // 2 pixels below baseline

        const underline_thick = if (self.underline_thickness > 0)
            @as(u32, @intFromFloat(@ceil(self.underline_thickness)))
        else
            1; // Default 1 pixel

        // Strikethrough: through middle of x-height
        const strikethrough_pos = baseline_pos - self.strikethroughPosition();
        const strikethrough_thick = underline_thick; // Same as underline

        // Overline: at cap height
        const overline_pos = baseline_pos - @as(u32, @intFromFloat(@round(self.cap_height)));
        const overline_thick = underline_thick;

        return .{
            .underline = @intCast(underline_pos),
            .underline_thickness = underline_thick,
            .strikethrough = @intCast(strikethrough_pos),
            .strikethrough_thickness = strikethrough_thick,
            .overline = @intCast(overline_pos),
            .overline_thickness = overline_thick,
        };
    }
};

/// Extract metrics from a FreeType face
pub fn extractMetrics(face: freetype.Face, font_size: FontSize) !FontMetrics {
    // Set the character size - for monospace fonts, set both width and height
    // to the same value to ensure proper aspect ratio
    const size_26_6 = font_size.to26Dot6();
    try face.setCharSize(size_26_6, size_26_6, font_size.dpi, font_size.dpi);

    // Get font metrics from FreeType
    const ft_metrics = face.handle.*.size.*.metrics;

    // Convert from 26.6 fixed-point to float
    const pixels_per_em = font_size.toPixels();
    const scale = pixels_per_em / @as(f32, @floatFromInt(face.handle.*.units_per_EM));

    // Extract basic metrics
    const ascent = @as(f32, @floatFromInt(ft_metrics.ascender)) / 64.0;
    const descent = @as(f32, @floatFromInt(ft_metrics.descender)) / 64.0;
    const line_gap = @as(f32, @floatFromInt(ft_metrics.height - (ft_metrics.ascender - ft_metrics.descender))) / 64.0;

    // Get additional metrics by measuring specific characters
    var max_width: f32 = 0;
    var cap_height: f32 = 0;
    var x_height: f32 = 0;

    // For monospace fonts, we should use the advance width, not the glyph bounds
    // The advance width determines how far the cursor moves, which is what we need
    // for proper character spacing in a terminal grid

    // Use FreeType's max_advance for monospace fonts
    // This is the standard width that all characters should occupy
    max_width = @as(f32, @floatFromInt(ft_metrics.max_advance)) / 64.0;

    // Verify this is actually a monospace font by checking a few characters
    // In a monospace font, all printable ASCII characters should have the same advance
    var is_monospace = true;
    var expected_advance: f32 = 0;
    var char: u8 = 'A'; // Start with a typical character
    while (char <= 'Z') : (char += 1) {
        if (face.getCharIndex(char)) |index| {
            if (face.loadGlyph(index, .{})) {
                const advance = @as(f32, @floatFromInt(face.handle.*.glyph.*.advance.x)) / 64.0;
                if (expected_advance == 0) {
                    expected_advance = advance;
                } else if (@abs(advance - expected_advance) > 0.1) {
                    is_monospace = false;
                    break;
                }
            } else |_| {}
        }
    }

    if (!is_monospace) {
        log.warn("Font does not appear to be monospace, terminal rendering may be incorrect", .{});
    }

    // Debug logging to understand the measurements
    log.info("Font metrics extracted: max_width={d:.2}, ascent={d:.2}, descent={d:.2}, line_gap={d:.2}", .{
        max_width, ascent, descent, line_gap
    });

    // Get cap height from 'M'
    if (face.getCharIndex('M')) |m_index| {
        try face.loadGlyph(m_index, .{ .render = true });
        cap_height = @as(f32, @floatFromInt(face.handle.*.glyph.*.bitmap_top));
    }

    // Measure 'x' for x-height
    if (face.getCharIndex('x')) |x_index| {
        try face.loadGlyph(x_index, .{ .render = true });
        x_height = @as(f32, @floatFromInt(face.handle.*.glyph.*.bitmap_top));
    }

    // Get underline metrics
    const underline_position = @as(f32, @floatFromInt(face.handle.*.underline_position)) * scale;
    const underline_thickness = @as(f32, @floatFromInt(face.handle.*.underline_thickness)) * scale;

    // Calculate average width (for monospace, should be same as max)
    var total_width: f32 = 0;
    var char_count: u32 = 0;

    // Measure printable ASCII characters (reuse char variable from above)
    char = 32; // Reset to space
    while (char <= 126) : (char += 1) {
        if (face.getCharIndex(char)) |index| {
            face.loadGlyph(index, .{}) catch continue;
            total_width += @as(f32, @floatFromInt(face.handle.*.glyph.*.advance.x)) / 64.0;
            char_count += 1;
        }
    }

    const average_width = if (char_count > 0) total_width / @as(f32, @floatFromInt(char_count)) else max_width;

    return FontMetrics{
        .ascent = ascent,
        .descent = descent,
        .line_gap = line_gap,
        .cap_height = cap_height,
        .x_height = x_height,
        .average_width = average_width,
        .max_width = max_width,
        .underline_position = underline_position,
        .underline_thickness = underline_thickness,
    };
}

/// Grid dimension calculator
pub const GridCalculator = struct {
    /// Calculate optimal grid dimensions from screen and cell sizes
    pub fn calculate(
        screen_width: u32,
        screen_height: u32,
        cell_width: u32,
        cell_height: u32,
        min_cols: u16,
        min_rows: u16,
    ) struct { cols: u16, rows: u16 } {
        // Calculate maximum possible grid
        const max_cols = screen_width / cell_width;
        const max_rows = screen_height / cell_height;

        // Ensure minimum dimensions (80x24 is standard VT100)
        // Cap at 512 for memory efficiency
        const cols = @max(min_cols, @min(max_cols, 512));
        const rows = @max(min_rows, @min(max_rows, 512));

        log.info("Grid calculation: screen={d}x{d}, cell={d}x{d}, grid={d}x{d}", .{
            screen_width, screen_height, cell_width, cell_height, cols, rows
        });

        return .{ .cols = @intCast(cols), .rows = @intCast(rows) };
    }

    /// Calculate cell size from desired grid dimensions
    pub fn cellSizeFromGrid(
        screen_width: u32,
        screen_height: u32,
        desired_cols: u16,
        desired_rows: u16,
    ) struct { width: u32, height: u32 } {
        const cell_width = screen_width / desired_cols;
        const cell_height = screen_height / desired_rows;

        log.info("Cell size from grid: screen={d}x{d}, grid={d}x{d}, cell={d}x{d}", .{
            screen_width, screen_height, desired_cols, desired_rows, cell_width, cell_height
        });

        return .{
            .width = cell_width,
            .height = cell_height,
        };
    }

    /// Calculate font size needed to fit desired grid
    pub fn fontSizeForGrid(
        screen_width: u32,
        screen_height: u32,
        desired_cols: u16,
        desired_rows: u16,
        dpi: u16,
    ) FontSize {
        // Calculate required cell size
        const cell = cellSizeFromGrid(screen_width, screen_height, desired_cols, desired_rows);

        // Estimate font size from cell height
        // Typical ratio: cell_height = font_size * 1.2 to 1.5
        // We'll use 1.35 as a good middle ground
        const estimated_pixels = @as(f32, @floatFromInt(cell.height)) / 1.35;

        return FontSize.fromPixels(estimated_pixels, dpi);
    }
};

/// Configuration for font and grid system
pub const Config = struct {
    /// Default font size in points
    default_font_size: f32 = 10.0,

    /// Minimum grid dimensions
    min_cols: u16 = 80,
    min_rows: u16 = 24,

    /// Maximum grid dimensions
    max_cols: u16 = 512,
    max_rows: u16 = 512,

    /// Whether to prefer exact grid fit over font size
    prefer_grid_fit: bool = false,

    /// Line height multiplier (1.0 = tight, 1.5 = loose)
    line_height_multiplier: f32 = 1.2,
};

// Tests
test "FontSize conversions" {
    const size = FontSize{ .points = 14.0, .dpi = 96 };

    // 14pt at 96 DPI = 14 * (96/72) = 18.67 pixels
    const pixels = size.toPixels();
    try std.testing.expectApproxEqRel(pixels, 18.67, 0.01);

    // Convert to 26.6 format
    const fixed = size.to26Dot6();
    try std.testing.expectEqual(fixed, 896); // 14 * 64

    // Round-trip conversion
    const size2 = FontSize.fromPixels(pixels, 96);
    try std.testing.expectApproxEqRel(size2.points, 14.0, 0.01);
}

test "FontMetrics calculations" {
    const metrics = FontMetrics{
        .ascent = 15.0,
        .descent = -5.0,
        .line_gap = 4.0,
        .cap_height = 12.0,
        .x_height = 8.0,
        .average_width = 10.0,
        .max_width = 10.0,
        .underline_position = -2.0,
        .underline_thickness = 1.0,
    };

    // Cell height = 15 - (-5) + 4 = 24
    try std.testing.expectEqual(metrics.cellHeight(), 24);

    // Cell width = max_width = 10
    try std.testing.expectEqual(metrics.cellWidth(), 10);

    // Baseline = 15 + 4/2 = 17
    try std.testing.expectEqual(metrics.baseline(), 17);

    // Strikethrough = x_height / 2 = 4
    try std.testing.expectEqual(metrics.strikethroughPosition(), 4);
}

test "GridCalculator" {
    // Test basic grid calculation
    const result = GridCalculator.calculate(1920, 1080, 10, 20, 80, 24);
    try std.testing.expectEqual(result.cols, 192);
    try std.testing.expectEqual(result.rows, 54);

    // Test minimum enforcement
    const result2 = GridCalculator.calculate(400, 300, 10, 20, 80, 24);
    try std.testing.expectEqual(result2.cols, 80); // Enforced minimum
    try std.testing.expectEqual(result2.rows, 24); // Enforced minimum

    // Test cell size from grid
    const cell = GridCalculator.cellSizeFromGrid(800, 600, 80, 30);
    try std.testing.expectEqual(cell.width, 10);
    try std.testing.expectEqual(cell.height, 20);
}