//! Simplified font system for Phase 1: Basic single-font text rendering
//!
//! This module provides a minimal FreeType wrapper for rendering ASCII text
//! with JetBrains Mono. Future phases will add Unicode support, caching,
//! and dynamic atlas packing.

const std = @import("std");
const freetype = @import("freetype");
const shaders = @import("shaders.zig");
const embedded_fonts = @import("embedded_fonts.zig");
const font_metrics = @import("font_metrics.zig");
const c = @cImport({
    @cInclude("android/log.h");
});

const log = std.log.scoped(.font_system);

/// Font style variants for bold/italic rendering
pub const FontStyle = enum(u2) {
    regular = 0,
    bold = 1,
    italic = 2,
    bold_italic = 3,
};

/// Atlas data for tracking glyph positions per style
pub const AtlasData = struct {
    positions: std.AutoHashMap(u21, [2]u32),
    bearings: std.AutoHashMap(u21, [2]i16), // Store bearings for each glyph
    next_x: u32,
    next_y: u32,
    row_height: u32,
};

/// Font system state
pub const FontSystem = struct {
    allocator: std.mem.Allocator,
    library: freetype.Library,
    face: freetype.Face, // Regular face
    face_bold: freetype.Face,
    face_italic: freetype.Face,
    face_bold_italic: freetype.Face,

    /// Font size configuration
    font_size: font_metrics.FontSize,

    /// Extracted font metrics
    metrics: font_metrics.FontMetrics,

    /// Calculated cell dimensions
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

    /// Atlas data per style (using shared atlas for all styles)
    atlas_regular: AtlasData,
    atlas_bold: AtlasData,
    atlas_italic: AtlasData,
    atlas_bold_italic: AtlasData,

    // Constants must come after all fields
    const ATLAS_COLS = 16; // 16 characters per row
    const ATLAS_PADDING = 2; // Padding between glyphs to prevent bleeding

    /// Common Unicode characters beyond ASCII (for terminal emulation)
    const UNICODE_CHARS = [_]u21{
        0x2588, // █ Full block (used in 256 color tests, progress bars, etc.)
        0x2500, // ─ Box drawing light horizontal (for strikethrough/dashed underline)
        0x2502, // │ Box drawing light vertical
        0x250C, // ┌ Box drawing light down and right
        0x2510, // ┐ Box drawing light down and left
        0x2514, // └ Box drawing light up and right
        0x2518, // ┘ Box drawing light up and left
        0x251C, // ├ Box drawing light vertical and right
        0x2524, // ┤ Box drawing light vertical and left
        0x252C, // ┬ Box drawing light down and horizontal
        0x2534, // ┴ Box drawing light up and horizontal
        0x253C, // ┼ Box drawing light vertical and horizontal
        0x2550, // ═ Box drawing double horizontal (for double underline)
        0x223C, // ∼ Tilde operator (for curly/wavy underline)
        0x2026, // … Horizontal ellipsis (for dotted underline)
        0x2581, // ▁ Lower one eighth block (for single underline)
    };

    /// Initialize font system with desired cell dimensions
    /// This calculates the appropriate font size to fit within the given cell size
    pub fn initWithCellSize(allocator: std.mem.Allocator, desired_cell_width: u32, desired_cell_height: u32, dpi: u16) !FontSystem {
        // Calculate font size needed for desired cell dimensions
        // Use GridCalculator to estimate the font size
        const font_size = font_metrics.GridCalculator.fontSizeForGrid(
            desired_cell_width * 80, // Assume 80 columns for calculation
            desired_cell_height * 24, // Assume 24 rows for calculation
            80,
            24,
            dpi
        );

        log.info("Initializing font system for cell size {d}x{d}, computed font size: {d:.1}pt at {d} DPI", .{
            desired_cell_width, desired_cell_height, font_size.points, dpi
        });

        var font_sys = try initWithFontSize(allocator, font_size);

        // Override the calculated cell dimensions with the requested dimensions
        // This ensures we fit exactly in the grid
        font_sys.cell_width = desired_cell_width;
        font_sys.cell_height = desired_cell_height;

        log.info("Using requested cell dimensions: {d}x{d}", .{ desired_cell_width, desired_cell_height });

        return font_sys;
    }

    /// Initialize font system with specific font size in points
    pub fn init(allocator: std.mem.Allocator, font_size_pts: f32, dpi: u16) !FontSystem {
        const font_size = font_metrics.FontSize{
            .points = font_size_pts,
            .dpi = dpi,
        };
        return try initWithFontSize(allocator, font_size);
    }

    /// Initialize with default font size
    pub fn initDefault(allocator: std.mem.Allocator, dpi: u16) !FontSystem {
        const font_size = font_metrics.FontSize.default(dpi);
        return try initWithFontSize(allocator, font_size);
    }

    fn initWithFontSize(allocator: std.mem.Allocator, font_size: font_metrics.FontSize) !FontSystem {
        const font_size_px = font_size.toPixels();
        log.info("Initializing font system with size {d:.1}pt ({d:.1}px) at {d} DPI", .{ font_size.points, font_size_px, font_size.dpi });

        // Initialize FreeType library
        var library = try freetype.Library.init();
        errdefer library.deinit();

        log.info("FreeType library initialized", .{});

        // Load regular font from embedded data
        const font_data = embedded_fonts.jetbrains_mono_regular;
        var face = try library.initMemoryFace(font_data, 0);
        errdefer face.deinit();

        log.info("Regular font face loaded ({d} bytes)", .{font_data.len});

        // Load bold font
        const font_data_bold = embedded_fonts.jetbrains_mono_bold;
        var face_bold = try library.initMemoryFace(font_data_bold, 0);
        errdefer face_bold.deinit();

        log.info("Bold font face loaded ({d} bytes)", .{font_data_bold.len});

        // Load italic font
        const font_data_italic = embedded_fonts.jetbrains_mono_italic;
        var face_italic = try library.initMemoryFace(font_data_italic, 0);
        errdefer face_italic.deinit();

        log.info("Italic font face loaded ({d} bytes)", .{font_data_italic.len});

        // Load bold-italic font
        const font_data_bold_italic = embedded_fonts.jetbrains_mono_bold_italic;
        var face_bold_italic = try library.initMemoryFace(font_data_bold_italic, 0);
        errdefer face_bold_italic.deinit();

        log.info("Bold-Italic font face loaded ({d} bytes)", .{font_data_bold_italic.len});

        // Set character size for all faces using the FontSize configuration
        // For monospace fonts, set both width and height to ensure proper aspect ratio
        const char_size_26_6 = font_size.to26Dot6();
        try face.setCharSize(char_size_26_6, char_size_26_6, font_size.dpi, font_size.dpi);
        try face_bold.setCharSize(char_size_26_6, char_size_26_6, font_size.dpi, font_size.dpi);
        try face_italic.setCharSize(char_size_26_6, char_size_26_6, font_size.dpi, font_size.dpi);
        try face_bold_italic.setCharSize(char_size_26_6, char_size_26_6, font_size.dpi, font_size.dpi);

        log.info("Font size set to {d:.1}pt at {d} DPI for all faces", .{ font_size.points, font_size.dpi });

        // Extract proper font metrics using the new system
        const metrics = try font_metrics.extractMetrics(face, font_size);

        // Calculate cell dimensions from metrics
        const cell_width = metrics.cellWidth();
        const cell_height = metrics.cellHeight();
        const baseline = @as(i32, @intCast(metrics.baseline()));

        // Calculate glyph size: Use cell_height plus padding
        // Don't round to power of 2 as it causes atlas misalignment
        const glyph_size = cell_height + ATLAS_PADDING * 2; // Add padding on both sides

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

        // Initialize atlas data structures for each style
        const atlas_regular = AtlasData{
            .positions = std.AutoHashMap(u21, [2]u32).init(allocator),
            .bearings = std.AutoHashMap(u21, [2]i16).init(allocator),
            .next_x = 0,
            .next_y = 0,
            .row_height = 0,
        };
        const atlas_bold = AtlasData{
            .positions = std.AutoHashMap(u21, [2]u32).init(allocator),
            .bearings = std.AutoHashMap(u21, [2]i16).init(allocator),
            .next_x = 0,
            .next_y = 0,
            .row_height = 0,
        };
        const atlas_italic = AtlasData{
            .positions = std.AutoHashMap(u21, [2]u32).init(allocator),
            .bearings = std.AutoHashMap(u21, [2]i16).init(allocator),
            .next_x = 0,
            .next_y = 0,
            .row_height = 0,
        };
        const atlas_bold_italic = AtlasData{
            .positions = std.AutoHashMap(u21, [2]u32).init(allocator),
            .bearings = std.AutoHashMap(u21, [2]i16).init(allocator),
            .next_x = 0,
            .next_y = 0,
            .row_height = 0,
        };

        return FontSystem{
            .allocator = allocator,
            .library = library,
            .face = face,
            .face_bold = face_bold,
            .face_italic = face_italic,
            .face_bold_italic = face_bold_italic,
            .font_size = font_size,
            .metrics = metrics,
            .cell_width = cell_width,
            .cell_height = cell_height,
            .baseline = baseline,
            .max_bearing_x = max_bearing_x,
            .min_bearing_x = min_bearing_x,
            .max_bearing_y = max_bearing_y,
            .min_bearing_y = min_bearing_y,
            .glyph_size = glyph_size,
            .atlas_regular = atlas_regular,
            .atlas_bold = atlas_bold,
            .atlas_italic = atlas_italic,
            .atlas_bold_italic = atlas_bold_italic,
        };
    }

    pub fn deinit(self: *FontSystem) void {
        self.atlas_regular.positions.deinit();
        self.atlas_regular.bearings.deinit();
        self.atlas_bold.positions.deinit();
        self.atlas_bold.bearings.deinit();
        self.atlas_italic.positions.deinit();
        self.atlas_italic.bearings.deinit();
        self.atlas_bold_italic.positions.deinit();
        self.atlas_bold_italic.bearings.deinit();
        self.face.deinit();
        self.face_bold.deinit();
        self.face_italic.deinit();
        self.face_bold_italic.deinit();
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
        log.info("Populating atlas ({d}x{d}) with characters for all styles", .{ atlas_width, atlas_height });

        // Allocate atlas buffer (R8 format = 1 byte per pixel)
        const atlas_data = try self.allocator.alloc(u8, atlas_width * atlas_height);
        errdefer self.allocator.free(atlas_data);

        // Clear atlas to transparent
        @memset(atlas_data, 0);

        // Render all four styles
        const styles = [_]FontStyle{ .regular, .bold, .italic, .bold_italic };
        for (styles) |style| {
            log.info("Populating atlas for style: {s}", .{@tagName(style)});

            // Render printable ASCII characters (32-126)
            var char: u8 = 32;
            while (char <= 126) : (char += 1) {
                const atlas_pos = self.getAtlasPos(char, style);
                const bearings = try self.renderGlyphToAtlas(char, style, atlas_pos, atlas_data, atlas_width, atlas_height);

                // Store position and bearings in atlas hashmap for this style
                // We need to access the mutable atlas directly, not through the const helper
                const atlas = switch (style) {
                    .regular => &self.atlas_regular,
                    .bold => &self.atlas_bold,
                    .italic => &self.atlas_italic,
                    .bold_italic => &self.atlas_bold_italic,
                };
                try atlas.positions.put(char, atlas_pos);
                try atlas.bearings.put(char, bearings);
            }

            // Render common Unicode characters
            for (UNICODE_CHARS) |unicode_char| {
                const atlas_pos = self.getAtlasPos(unicode_char, style);
                const bearings = try self.renderGlyphToAtlasUnicode(unicode_char, style, atlas_pos, atlas_data, atlas_width, atlas_height);

                // Store position and bearings in atlas hashmap for this style
                // We need to access the mutable atlas directly, not through the const helper
                const atlas = switch (style) {
                    .regular => &self.atlas_regular,
                    .bold => &self.atlas_bold,
                    .italic => &self.atlas_italic,
                    .bold_italic => &self.atlas_bold_italic,
                };
                try atlas.positions.put(unicode_char, atlas_pos);
                try atlas.bearings.put(unicode_char, bearings);
            }
        }

        log.info("Atlas populated with {d} ASCII + {d} Unicode characters for all 4 styles", .{ 127 - 32, UNICODE_CHARS.len });

        return atlas_data;
    }

    /// Get atlas data for a given style
    fn getAtlasForStyle(self: *const FontSystem, style: FontStyle) *const AtlasData {
        return switch (style) {
            .regular => &self.atlas_regular,
            .bold => &self.atlas_bold,
            .italic => &self.atlas_italic,
            .bold_italic => &self.atlas_bold_italic,
        };
    }

    /// Get atlas position for a character with specific font style
    /// The atlas is organized with different styles in quadrants:
    /// Top-left: regular, Top-right: bold
    /// Bottom-left: italic, Bottom-right: bold_italic
    fn getAtlasPos(self: FontSystem, codepoint: u21, style: FontStyle) [2]u32 {
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

        // Base position within the quadrant (including padding)
        const slot_size = self.glyph_size + ATLAS_PADDING;
        const base_x: u32 = col * slot_size + ATLAS_PADDING / 2; // Add half padding to start
        const base_y: u32 = row * slot_size + ATLAS_PADDING / 2;

        // Calculate number of rows needed for all characters in one style
        const num_chars: u32 = 95 + @as(u32, @intCast(UNICODE_CHARS.len));
        const num_rows: u32 = (num_chars + ATLAS_COLS - 1) / ATLAS_COLS;
        const quadrant_width = ATLAS_COLS * slot_size;
        const quadrant_height = num_rows * slot_size;

        // Offset based on style (organize in 2x2 grid)
        const style_offset: [2]u32 = switch (style) {
            .regular => .{ 0, 0 }, // Top-left
            .bold => .{ quadrant_width, 0 }, // Top-right
            .italic => .{ 0, quadrant_height }, // Bottom-left
            .bold_italic => .{ quadrant_width, quadrant_height }, // Bottom-right
        };

        return .{ base_x + style_offset[0], base_y + style_offset[1] };
    }

    /// Render a single ASCII glyph into the atlas at the specified position
    /// Returns the bearing values for this glyph
    fn renderGlyphToAtlas(
        self: *FontSystem,
        char: u8,
        style: FontStyle,
        atlas_pos: [2]u32,
        atlas_data: []u8,
        atlas_width: u32,
        atlas_height: u32,
    ) ![2]i16 {
        // Select the appropriate face and render the glyph
        const face = switch (style) {
            .regular => self.face,
            .bold => self.face_bold,
            .italic => self.face_italic,
            .bold_italic => self.face_bold_italic,
        };

        const glyph_index = face.getCharIndex(char) orelse return .{ 0, 0 };
        try face.loadGlyph(glyph_index, .{ .render = true });
        try face.renderGlyph(.normal);

        const glyph = face.handle.*.glyph;
        const bitmap = glyph.*.bitmap;

        // Get bitmap dimensions
        const bmp_width = bitmap.width;
        const bmp_height = bitmap.rows;

        // Get bearings
        const bearing_x = @as(i16, @intCast(glyph.*.bitmap_left));
        const bearing_y = @as(i16, @intCast(glyph.*.bitmap_top));

        const bmp_buffer = bitmap.buffer orelse return .{ bearing_x, bearing_y }; // Empty glyph (space, etc.)

        // Use bearing_x for horizontal positioning (don't center)
        // This preserves the glyph's natural positioning relative to its origin
        // bearing_x is the horizontal offset from the origin to the left edge of the bitmap
        const x_offset = if (bearing_x >= 0)
            @as(u32, @intCast(bearing_x))
        else
            0; // Clamp negative bearings to prevent underflow

        // Y offset: Position relative to baseline
        // Place baseline at a consistent position within the slot (3/4 down from top)
        const baseline_pos = (self.glyph_size * 3) / 4;
        // bearing_y (bitmap_top) is the distance from baseline to top of bitmap
        // y_offset positions the top of the bitmap relative to the slot top
        const y_offset = baseline_pos - @as(u32, @intCast(bearing_y));

        // Copy bitmap data to atlas (clipping to glyph_size to stay within padded area)
        var y: u32 = 0;
        while (y < bmp_height) : (y += 1) {
            const atlas_y = atlas_pos[1] + y_offset + y;
            if (atlas_y >= atlas_height) break;
            // Don't render beyond our allocated slot
            if (y_offset + y >= self.glyph_size) break;

            var x: u32 = 0;
            while (x < bmp_width) : (x += 1) {
                const atlas_x = atlas_pos[0] + x_offset + x;
                if (atlas_x >= atlas_width) break;
                // Don't render beyond our allocated slot
                if (x_offset + x >= self.glyph_size) break;

                const atlas_index = atlas_y * atlas_width + atlas_x;
                const bmp_index = y * bmp_width + x;

                atlas_data[atlas_index] = bmp_buffer[bmp_index];
            }
        }

        // Return the bearing values
        return .{ bearing_x, bearing_y };
    }

    /// Render a single Unicode glyph into the atlas at the specified position
    /// Returns the bearing values for this glyph
    fn renderGlyphToAtlasUnicode(
        self: *FontSystem,
        codepoint: u21,
        style: FontStyle,
        atlas_pos: [2]u32,
        atlas_data: []u8,
        atlas_width: u32,
        atlas_height: u32,
    ) ![2]i16 {
        // Select the appropriate face and render the glyph
        const face = switch (style) {
            .regular => self.face,
            .bold => self.face_bold,
            .italic => self.face_italic,
            .bold_italic => self.face_bold_italic,
        };

        const glyph_index = face.getCharIndex(codepoint) orelse return .{ 0, 0 };
        try face.loadGlyph(glyph_index, .{ .render = true });
        try face.renderGlyph(.normal);

        const glyph = face.handle.*.glyph;
        const bitmap = glyph.*.bitmap;

        // Get bitmap dimensions
        const bmp_width = bitmap.width;
        const bmp_height = bitmap.rows;

        // Get bearings
        const bearing_x = @as(i16, @intCast(glyph.*.bitmap_left));
        const bearing_y = @as(i16, @intCast(glyph.*.bitmap_top));

        const bmp_buffer = bitmap.buffer orelse return .{ bearing_x, bearing_y }; // Empty glyph (space, etc.)

        // Use bearing_x for horizontal positioning (don't center)
        // This preserves the glyph's natural positioning relative to its origin
        // bearing_x is the horizontal offset from the origin to the left edge of the bitmap
        const x_offset = if (bearing_x >= 0)
            @as(u32, @intCast(bearing_x))
        else
            0; // Clamp negative bearings to prevent underflow

        // Y offset: Position relative to baseline
        // Place baseline at a consistent position within the slot (3/4 down from top)
        const baseline_pos = (self.glyph_size * 3) / 4;
        // bearing_y (bitmap_top) is the distance from baseline to top of bitmap
        // y_offset positions the top of the bitmap relative to the slot top
        const y_offset = baseline_pos - @as(u32, @intCast(bearing_y));

        // Copy bitmap data to atlas (clipping to glyph_size to stay within padded area)
        var y: u32 = 0;
        while (y < bmp_height) : (y += 1) {
            const atlas_y = atlas_pos[1] + y_offset + y;
            if (atlas_y >= atlas_height) break;
            // Don't render beyond our allocated slot
            if (y_offset + y >= self.glyph_size) break;

            var x: u32 = 0;
            while (x < bmp_width) : (x += 1) {
                const atlas_x = atlas_pos[0] + x_offset + x;
                if (atlas_x >= atlas_width) break;
                // Don't render beyond our allocated slot
                if (x_offset + x >= self.glyph_size) break;

                const atlas_index = atlas_y * atlas_width + atlas_x;
                const bmp_index = y * bmp_width + x;

                atlas_data[atlas_index] = bmp_buffer[bmp_index];
            }
        }

        // Return the bearing values
        return .{ bearing_x, bearing_y };
    }

    /// Generate CellText instance for rendering a character at a grid position
    /// Supports ASCII 32-126 and common Unicode characters. Out-of-range codepoints render as space.
    ///
    /// BEARING IMPLEMENTATION:
    /// Bearings are now properly implemented. Glyphs are rendered to the atlas without
    /// centering, preserving their original positioning. The vertex shader uses the
    /// bearing values to correctly position each glyph within its cell.
    ///
    /// This approach ensures:
    /// - Proper positioning of italic characters that lean outside cell boundaries
    /// - Correct rendering of characters with negative bearings
    /// - Accurate placement of special symbols and Unicode characters
    /// - Better visual fidelity for fonts with complex metrics
    pub fn makeCellText(
        self: *FontSystem,
        codepoint: u21,
        grid_col: u16,
        grid_row: u16,
        color: [4]u8,
        attributes: shaders.CellText.Attributes,
    ) shaders.CellText {
        // Determine font style from attributes
        const style: FontStyle = if (attributes.bold and attributes.italic)
            .bold_italic
        else if (attributes.bold)
            .bold
        else if (attributes.italic)
            .italic
        else
            .regular;

        // Get atlas position for this style
        const atlas_pos = self.getAtlasPos(codepoint, style);

        // Look up bearing values for proper glyph positioning
        const atlas = self.getAtlasForStyle(style);
        const bearings = atlas.bearings.get(codepoint) orelse .{ 0, 0 };

        return shaders.CellText{
            .glyph_pos = atlas_pos,
            .glyph_size = .{ self.glyph_size, self.glyph_size },
            .bearings = bearings, // Use actual bearings for accurate positioning
            .grid_pos = .{ grid_col, grid_row },
            .color = color,
            .atlas = .grayscale,
            .bools = .{},
            .attributes = attributes,
        };
    }

    /// Calculate required atlas dimensions for the font size
    /// Returns [width, height] in pixels
    /// Atlas is organized in a 2x2 grid to hold all 4 font styles (regular, bold, italic, bold_italic)
    pub fn getAtlasDimensions(self: FontSystem) [2]u32 {
        // ASCII printable chars: 32-126 = 95 characters + Unicode chars
        const num_chars: u32 = 95 + @as(u32, @intCast(UNICODE_CHARS.len));
        const num_rows: u32 = (num_chars + ATLAS_COLS - 1) / ATLAS_COLS; // Ceiling division

        // Single quadrant dimensions (including padding)
        const slot_size: u32 = self.glyph_size + ATLAS_PADDING;
        const quadrant_width: u32 = ATLAS_COLS * slot_size;
        const quadrant_height: u32 = num_rows * slot_size;

        // Total atlas is 2x2 grid of quadrants (4 styles)
        const width: u32 = quadrant_width * 2;
        const height: u32 = quadrant_height * 2;

        return .{ width, height };
    }
};
