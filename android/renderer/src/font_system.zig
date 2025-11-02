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

    /// Dynamic atlas layout based on font size
    glyph_size: u32, // Calculated based on font size
    const ATLAS_COLS = 16; // 16 characters per row

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

        return FontSystem{
            .allocator = allocator,
            .library = library,
            .face = face,
            .cell_width = cell_width,
            .cell_height = cell_height,
            .baseline = baseline,
            .glyph_size = glyph_size,
        };
    }

    pub fn deinit(self: *FontSystem) void {
        self.face.deinit();
        self.library.deinit();
        log.info("Font system deinitialized", .{});
    }

    /// Get cell dimensions for updating renderer uniforms
    pub fn getCellSize(self: FontSystem) [2]f32 {
        return .{
            @as(f32, @floatFromInt(self.cell_width)),
            @as(f32, @floatFromInt(self.cell_height)),
        };
    }

    /// Render ASCII characters into atlas and return atlas data
    pub fn populateAtlas(
        self: *FontSystem,
        atlas_width: u32,
        atlas_height: u32,
    ) ![]u8 {
        log.info("Populating atlas ({d}x{d}) with ASCII characters", .{ atlas_width, atlas_height });

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

        log.info("Atlas populated with {d} characters", .{127 - 32});

        return atlas_data;
    }

    /// Get atlas position for a character (simple grid layout)
    fn getAtlasPos(self: FontSystem, char: u8) [2]u32 {
        if (char < 32 or char > 126) return .{ 0, 0 };

        const index = char - 32; // Offset to start at 0
        const col = index % ATLAS_COLS;
        const row = index / ATLAS_COLS;

        // Cast to u32 before multiplication to prevent u8 overflow
        const pos_x: u32 = @as(u32, col) * self.glyph_size;
        const pos_y: u32 = @as(u32, row) * self.glyph_size;

        return .{ pos_x, pos_y };
    }

    /// Render a single glyph into the atlas at the specified position
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

    /// Generate CellText instance for rendering a character at a grid position
    pub fn makeCellText(
        self: FontSystem,
        char: u8,
        grid_col: u16,
        grid_row: u16,
        color: [4]u8,
    ) shaders.CellText {
        const atlas_pos = self.getAtlasPos(char);

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
        // ASCII printable chars: 32-126 = 95 characters
        const num_chars = 95;
        const num_rows = (num_chars + ATLAS_COLS - 1) / ATLAS_COLS; // Ceiling division

        const width = ATLAS_COLS * self.glyph_size;
        const height = num_rows * self.glyph_size;

        return .{ width, height };
    }
};
