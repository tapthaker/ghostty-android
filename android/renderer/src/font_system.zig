//! Simplified font system for Phase 1: Basic single-font text rendering
//!
//! This module provides a minimal FreeType wrapper for rendering ASCII text
//! with JetBrains Mono. Future phases will add Unicode support, caching,
//! and dynamic atlas packing.

const std = @import("std");
const freetype = @import("freetype");
const shaders = @import("shaders.zig");
const embedded_fonts = @import("embedded_fonts.zig");
const c = @cImport({
    @cInclude("android/log.h");
});

const log = std.log.scoped(.font_system);

/// Font system state
pub const FontSystem = struct {
    allocator: std.mem.Allocator,
    library: freetype.Library,
    face: freetype.Face,

    /// Font metrics
    cell_width: u32,
    cell_height: u32,
    baseline: i32,

    /// Maximum glyph bearing values (for viewport padding calculations)
    max_bearing_x: i32, // Maximum left bearing (positive = glyph extends left of cell origin)
    min_bearing_x: i32, // Minimum left bearing (negative = glyph starts right of cell origin)
    max_bearing_y: i32, // Maximum top bearing (positive = glyph extends above baseline)
    min_bearing_y: i32, // Minimum top bearing (negative = glyph extends below baseline)

    /// Dynamic atlas layout based on font size
    glyph_size: u32, // Calculated based on font size
    const ATLAS_COLS = 16; // 16 characters per row

    /// Common Unicode characters beyond ASCII (for terminal emulation)
    const UNICODE_CHARS = [_]u21{
        0x2588, // █ Full block (used in 256 color tests, progress bars, etc.)
    };

    pub fn init(allocator: std.mem.Allocator, font_size_px: u32) !FontSystem {
        log.info("Initializing font system with size {d}px", .{font_size_px});

        // Initialize FreeType library
        var library = try freetype.Library.init();
        errdefer library.deinit();

        log.info("FreeType library initialized", .{});

        // Load font from embedded data
        const font_data = embedded_fonts.jetbrains_mono_regular;
        var face = try library.initMemoryFace(font_data, 0);
        errdefer face.deinit();

        log.info("Font face loaded ({d} bytes)", .{font_data.len});

        // Set character size (using 96 DPI)
        // FreeType uses 1/64th of points, so multiply pixel size by 64
        // For pixel-based sizing, we use the formula: pixels * 64 * 72 / dpi
        const dpi = 96;
        const char_height_26_6: i32 = @intCast((font_size_px * 64 * 72) / dpi);
        try face.setCharSize(0, char_height_26_6, dpi, dpi);

        log.info("Font size set to {d}px at {d} DPI", .{ font_size_px, dpi });

        // Calculate font metrics by measuring a typical character
        const char_m_index = face.getCharIndex('M') orelse return error.GlyphNotFound;
        try face.loadGlyph(char_m_index, .{ .render = true });
        try face.renderGlyph(.normal);
        const glyph = face.handle.*.glyph;

        const cell_width = @as(u32, @intCast(glyph.*.advance.x)) >> 6; // Convert 26.6 to pixels
        const cell_height = font_size_px;
        const baseline = @as(i32, @intCast(glyph.*.bitmap_top));

        // Calculate glyph size: 1.5x font size, rounded up to power of 2 for better texture performance
        const glyph_size_calc = (font_size_px * 3) / 2;
        var glyph_size: u32 = 16; // Minimum size
        while (glyph_size < glyph_size_calc) : (glyph_size *= 2) {}

        log.info("Font metrics: cell={d}x{d}, baseline={d}, glyph_size={d}", .{ cell_width, cell_height, baseline, glyph_size });

        // Calculate maximum bearing values across all ASCII printable characters
        var max_bearing_x: i32 = 0;
        var min_bearing_x: i32 = 0;
        var max_bearing_y: i32 = 0;
        var min_bearing_y: i32 = 0;

        // Iterate through ASCII printable characters (32-126)
        var char: u8 = 32;
        while (char <= 126) : (char += 1) {
            const char_index = face.getCharIndex(char) orelse continue;
            face.loadGlyph(char_index, .{ .render = true }) catch continue;
            const glyph_metrics = face.handle.*.glyph;

            const bearing_x = @as(i32, @intCast(glyph_metrics.*.bitmap_left));
            const bearing_y = @as(i32, @intCast(glyph_metrics.*.bitmap_top));
            const glyph_width = @as(i32, @intCast(glyph_metrics.*.bitmap.width));
            const glyph_height = @as(i32, @intCast(glyph_metrics.*.bitmap.rows));

            // Track maximum extents
            max_bearing_x = @max(max_bearing_x, bearing_x);
            min_bearing_x = @min(min_bearing_x, bearing_x);
            max_bearing_y = @max(max_bearing_y, bearing_y);
            min_bearing_y = @min(min_bearing_y, bearing_y - glyph_height);

            // Also check right edge overflow (glyph extends past advance width)
            const right_edge = bearing_x + glyph_width;
            const advance_x = @as(i32, @intCast(glyph_metrics.*.advance.x >> 6));
            if (right_edge > advance_x) {
                max_bearing_x = @max(max_bearing_x, right_edge - advance_x);
            }
        }

        log.info("Bearing extents: x=[{d}, {d}], y=[{d}, {d}]", .{ min_bearing_x, max_bearing_x, min_bearing_y, max_bearing_y });

        return FontSystem{
            .allocator = allocator,
            .library = library,
            .face = face,
            .cell_width = cell_width,
            .cell_height = cell_height,
            .baseline = baseline,
            .max_bearing_x = max_bearing_x,
            .min_bearing_x = min_bearing_x,
            .max_bearing_y = max_bearing_y,
            .min_bearing_y = min_bearing_y,
            .glyph_size = glyph_size,
        };
    }

    pub fn deinit(self: *FontSystem) void {
        self.face.deinit();
        self.library.deinit();
        log.info("Font system deinitialized", .{});
    }

    /// Get required padding in pixels to prevent glyph clipping at viewport edges
    /// Returns padding needed on right/bottom edges (left/top are handled by cell positioning)
    pub fn getViewportPadding(self: FontSystem) struct { right: u32, bottom: u32 } {
        // Right padding: Use cell_width + max_bearing to account for:
        // 1. The full width of the rightmost cell
        // 2. Any glyph overhang due to bearings
        // This ensures glyphs in the rightmost column have space for their full rendered width
        const bearing_overhang = if (self.max_bearing_x > 0) @as(u32, @intCast(self.max_bearing_x)) else 0;
        const right_padding = self.cell_width + bearing_overhang;

        // Bottom padding: Use cell_height + bearing to be consistent
        const bearing_underhang = if (self.min_bearing_y < 0) @as(u32, @intCast(-self.min_bearing_y)) else 0;
        const bottom_padding = self.cell_height + bearing_underhang;

        return .{ .right = right_padding, .bottom = bottom_padding };
    }

    /// Get cell dimensions for updating renderer uniforms
    pub fn getCellSize(self: FontSystem) [2]f32 {
        return .{
            @as(f32, @floatFromInt(self.cell_width)),
            @as(f32, @floatFromInt(self.cell_height)),
        };
    }

    /// Render ASCII and common Unicode characters into atlas and return atlas data
    pub fn populateAtlas(
        self: *FontSystem,
        atlas_width: u32,
        atlas_height: u32,
    ) ![]u8 {
        log.info("Populating atlas ({d}x{d}) with characters", .{ atlas_width, atlas_height });

        // Allocate atlas buffer (R8 format = 1 byte per pixel)
        const atlas_data = try self.allocator.alloc(u8, atlas_width * atlas_height);
        errdefer self.allocator.free(atlas_data);

        // Clear atlas to transparent
        @memset(atlas_data, 0);

        // Render printable ASCII characters (32-126)
        var char: u8 = 32;
        while (char <= 126) : (char += 1) {
            const atlas_pos = self.getAtlasPos(char);
            try self.renderGlyphToAtlas(char, atlas_pos, atlas_data, atlas_width, atlas_height);
        }

        // Render common Unicode characters
        for (UNICODE_CHARS) |unicode_char| {
            const atlas_pos = self.getAtlasPos(unicode_char);
            try self.renderGlyphToAtlasUnicode(unicode_char, atlas_pos, atlas_data, atlas_width, atlas_height);
        }

        log.info("Atlas populated with {d} ASCII + {d} Unicode characters", .{ 127 - 32, UNICODE_CHARS.len });

        return atlas_data;
    }

    /// Get atlas position for a character (simple grid layout)
    /// Supports ASCII 32-126 and common Unicode characters. Out-of-range chars use space (32).
    fn getAtlasPos(self: FontSystem, codepoint: u21) [2]u32 {
        var index: u32 = 0;

        // Check if it's printable ASCII (32-126)
        if (codepoint >= 32 and codepoint <= 126) {
            index = codepoint - 32; // Offset to start at 0
        } else {
            // Check if it's a supported Unicode character
            var found = false;
            for (UNICODE_CHARS, 0..) |unicode_char, i| {
                if (codepoint == unicode_char) {
                    // Place Unicode chars after ASCII (95 ASCII chars from 32-126)
                    index = 95 + @as(u32, @intCast(i));
                    found = true;
                    break;
                }
            }
            if (!found) {
                // Use space for unsupported characters
                index = 0; // Space is at index 0 (codepoint 32 - 32 = 0)
            }
        }

        const col = index % ATLAS_COLS;
        const row = index / ATLAS_COLS;

        // Cast to u32 before multiplication to prevent overflow
        const pos_x: u32 = col * self.glyph_size;
        const pos_y: u32 = row * self.glyph_size;

        return .{ pos_x, pos_y };
    }

    /// Render a single ASCII glyph into the atlas at the specified position
    fn renderGlyphToAtlas(
        self: *FontSystem,
        char: u8,
        atlas_pos: [2]u32,
        atlas_data: []u8,
        atlas_width: u32,
        atlas_height: u32,
    ) !void {
        // Load and render glyph
        const glyph_index = self.face.getCharIndex(char) orelse return; // Skip if glyph doesn't exist
        try self.face.loadGlyph(glyph_index, .{ .render = true });
        try self.face.renderGlyph(.normal);
        const glyph = self.face.handle.*.glyph;
        const bitmap = glyph.*.bitmap;

        // Get bitmap dimensions
        const bmp_width = bitmap.width;
        const bmp_height = bitmap.rows;
        const bmp_buffer = bitmap.buffer orelse return; // Empty glyph (space, etc.)

        // Calculate position with baseline alignment
        // Horizontally center the glyph
        const x_offset = (self.glyph_size - bmp_width) / 2;

        // Vertically align based on baseline
        // Place baseline at a consistent position within the slot (3/4 down from top)
        const baseline_pos = (self.glyph_size * 3) / 4;
        const bitmap_top = glyph.*.bitmap_top;
        // y_offset positions the top of the bitmap relative to the slot top
        const y_offset = baseline_pos - @as(u32, @intCast(bitmap_top));

        // Copy bitmap data to atlas
        var y: u32 = 0;
        while (y < bmp_height) : (y += 1) {
            const atlas_y = atlas_pos[1] + y_offset + y;
            if (atlas_y >= atlas_height) break;

            var x: u32 = 0;
            while (x < bmp_width) : (x += 1) {
                const atlas_x = atlas_pos[0] + x_offset + x;
                if (atlas_x >= atlas_width) break;

                const atlas_index = atlas_y * atlas_width + atlas_x;
                const bmp_index = y * bmp_width + x;

                atlas_data[atlas_index] = bmp_buffer[bmp_index];
            }
        }
    }

    /// Render a single Unicode glyph into the atlas at the specified position
    fn renderGlyphToAtlasUnicode(
        self: *FontSystem,
        codepoint: u21,
        atlas_pos: [2]u32,
        atlas_data: []u8,
        atlas_width: u32,
        atlas_height: u32,
    ) !void {
        // Load and render glyph
        const glyph_index = self.face.getCharIndex(codepoint) orelse return; // Skip if glyph doesn't exist
        try self.face.loadGlyph(glyph_index, .{ .render = true });
        try self.face.renderGlyph(.normal);
        const glyph = self.face.handle.*.glyph;
        const bitmap = glyph.*.bitmap;

        // Get bitmap dimensions
        const bmp_width = bitmap.width;
        const bmp_height = bitmap.rows;
        const bmp_buffer = bitmap.buffer orelse return; // Empty glyph (space, etc.)

        // Calculate position with baseline alignment
        // Horizontally center the glyph
        const x_offset = (self.glyph_size - bmp_width) / 2;

        // Vertically align based on baseline
        // Place baseline at a consistent position within the slot (3/4 down from top)
        const baseline_pos = (self.glyph_size * 3) / 4;
        const bitmap_top = glyph.*.bitmap_top;
        // y_offset positions the top of the bitmap relative to the slot top
        const y_offset = baseline_pos - @as(u32, @intCast(bitmap_top));

        // Copy bitmap data to atlas
        var y: u32 = 0;
        while (y < bmp_height) : (y += 1) {
            const atlas_y = atlas_pos[1] + y_offset + y;
            if (atlas_y >= atlas_height) break;

            var x: u32 = 0;
            while (x < bmp_width) : (x += 1) {
                const atlas_x = atlas_pos[0] + x_offset + x;
                if (atlas_x >= atlas_width) break;

                const atlas_index = atlas_y * atlas_width + atlas_x;
                const bmp_index = y * bmp_width + x;

                atlas_data[atlas_index] = bmp_buffer[bmp_index];
            }
        }
    }

    /// Generate CellText instance for rendering a character at a grid position
    /// Supports ASCII 32-126 and common Unicode characters. Out-of-range codepoints render as space.
    pub fn makeCellText(
        self: FontSystem,
        codepoint: u21,
        grid_col: u16,
        grid_row: u16,
        color: [4]u8,
    ) shaders.CellText {
        const atlas_pos = self.getAtlasPos(codepoint);

        return shaders.CellText{
            .glyph_pos = atlas_pos,
            .glyph_size = .{ self.glyph_size, self.glyph_size },
            .bearings = .{ 0, 0 }, // Simplified for Phase 1
            .grid_pos = .{ grid_col, grid_row },
            .color = color,
            .atlas = .grayscale,
            .bools = .{},
        };
    }

    /// Calculate required atlas dimensions for the font size
    /// Returns [width, height] in pixels
    pub fn getAtlasDimensions(self: FontSystem) [2]u32 {
        // ASCII printable chars: 32-126 = 95 characters + Unicode chars
        const num_chars: u32 = 95 + @as(u32, @intCast(UNICODE_CHARS.len));
        const num_rows: u32 = (num_chars + ATLAS_COLS - 1) / ATLAS_COLS; // Ceiling division

        const width: u32 = ATLAS_COLS * self.glyph_size;
        const height: u32 = num_rows * self.glyph_size;

        return .{ width, height };
    }
};
