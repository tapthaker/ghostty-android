//! Font Collection - manages multiple fonts with style variants and fallback chains
//!
//! This module provides a unified interface for managing multiple font faces,
//! including regular, bold, italic variants and fallback fonts for Unicode coverage.
//! Follows the Ghostty pattern of deferred loading and metadata-first approach.

const std = @import("std");
const freetype = @import("freetype");
const embedded_fonts = @import("embedded_fonts.zig");
const font_metrics = @import("font_metrics.zig");

const log = std.log.scoped(.font_collection);

/// Font style variants
pub const FontStyle = enum(u2) {
    regular = 0,
    bold = 1,
    italic = 2,
    bold_italic = 3,

    pub fn fromFlags(bold: bool, italic: bool) FontStyle {
        if (bold and italic) return .bold_italic;
        if (bold) return .bold;
        if (italic) return .italic;
        return .regular;
    }
};

/// Font source type
pub const FontSource = union(enum) {
    embedded: []const u8, // Embedded font data
    file_path: []const u8, // Path to font file
    system_name: []const u8, // System font name (for Android font discovery)
};

/// Information about a loaded font face
pub const FontFace = struct {
    face: freetype.Face,
    source: FontSource,
    /// Unicode ranges this font covers well
    /// (used for fallback selection)
    coverage_hint: ?UnicodeRangeHint = null,

    pub const UnicodeRangeHint = enum {
        latin, // Basic Latin + Latin-1 Supplement
        cjk, // CJK Unified Ideographs
        emoji, // Emoji ranges
        arabic, // Arabic script
        devanagari, // Devanagari script
        symbols, // Mathematical and technical symbols
        full, // Full Unicode coverage (fallback font)
    };

    pub fn deinit(self: *FontFace) void {
        self.face.deinit();
    }

    /// Check if this font has a glyph for the given codepoint
    /// This is a quick check without rendering
    pub fn hasGlyph(self: *const FontFace, codepoint: u21) bool {
        // Safety check: ensure face handle is valid (C pointer check)
        // C pointers are null when their address is 0
        if (@intFromPtr(self.face.handle) == 0) {
            return false;
        }
        const glyph_index = self.face.getCharIndex(codepoint);
        return glyph_index != null and glyph_index.? != 0;
    }
};

/// A set of font faces for different styles
pub const FontFamily = struct {
    regular: ?FontFace = null,
    bold: ?FontFace = null,
    italic: ?FontFace = null,
    bold_italic: ?FontFace = null,

    pub fn deinit(self: *FontFamily) void {
        if (self.regular) |*f| f.deinit();
        if (self.bold) |*f| f.deinit();
        if (self.italic) |*f| f.deinit();
        if (self.bold_italic) |*f| f.deinit();
    }

    /// Get face for specific style, falling back to regular if not available
    pub fn getFace(self: *const FontFamily, style: FontStyle) ?*const FontFace {
        return switch (style) {
            .regular => if (self.regular) |*f| f else null,
            .bold => if (self.bold) |*f| f else if (self.regular) |*f| f else null,
            .italic => if (self.italic) |*f| f else if (self.regular) |*f| f else null,
            .bold_italic => if (self.bold_italic) |*f| f else if (self.bold) |*f| f else if (self.italic) |*f| f else if (self.regular) |*f| f else null,
        };
    }
};

/// Font collection manages all loaded fonts
pub const FontCollection = struct {
    allocator: std.mem.Allocator,
    library: freetype.Library,

    /// Primary font family (user's chosen font)
    primary: FontFamily,

    /// Fallback fonts for Unicode coverage
    /// These are loaded on-demand when needed
    fallbacks: std.ArrayList(FontFamily),

    /// Font size configuration
    font_size: font_metrics.FontSize,

    /// Android system font paths
    const AndroidFonts = struct {
        const system_path = "/system/fonts/";
        const roboto_mono = system_path ++ "RobotoMono-Regular.ttf";
        const roboto_mono_bold = system_path ++ "RobotoMono-Bold.ttf";
        const roboto_mono_italic = system_path ++ "RobotoMono-Italic.ttf";
        const roboto_mono_bold_italic = system_path ++ "RobotoMono-BoldItalic.ttf";

        const noto_cjk = system_path ++ "NotoSansCJK-Regular.ttc";
        const noto_emoji = system_path ++ "NotoColorEmoji.ttf";
        const droid_sans = system_path ++ "DroidSans.ttf";
        const droid_sans_bold = system_path ++ "DroidSans-Bold.ttf";
    };

    pub fn init(allocator: std.mem.Allocator, font_size: font_metrics.FontSize) !FontCollection {
        var library = try freetype.Library.init();
        errdefer library.deinit();

        var collection = FontCollection{
            .allocator = allocator,
            .library = library,
            .primary = .{},
            // Pre-allocate capacity for fallback fonts to prevent reallocation
            // which would invalidate cached pointers in CodepointResolver
            .fallbacks = try std.ArrayList(FontFamily).initCapacity(allocator, 4),
            .font_size = font_size,
        };

        // Load primary font family (JetBrains Mono for now)
        try collection.loadPrimaryFonts();

        // Load fallback fonts eagerly to avoid issues during rendering
        // Pre-allocated capacity prevents ArrayList reallocation
        try collection.loadFallbackFonts();
        log.info("Loaded {} fallback font families", .{collection.fallbacks.items.len});

        return collection;
    }

    pub fn deinit(self: *FontCollection) void {
        self.primary.deinit();
        for (self.fallbacks.items) |*family| {
            family.deinit();
        }
        self.fallbacks.deinit(self.allocator);
        self.library.deinit();
    }

    /// Load the primary font family
    fn loadPrimaryFonts(self: *FontCollection) !void {
        const font_size_px = self.font_size.toPixels();
        const font_size_int = @as(i32, @intFromFloat(@round(font_size_px)));

        // Load JetBrains Mono as primary font (embedded)
        self.primary.regular = try self.loadEmbeddedFont(
            embedded_fonts.jetbrains_mono_regular,
            font_size_int,
            .latin,
        );

        self.primary.bold = try self.loadEmbeddedFont(
            embedded_fonts.jetbrains_mono_bold,
            font_size_int,
            .latin,
        );

        self.primary.italic = try self.loadEmbeddedFont(
            embedded_fonts.jetbrains_mono_italic,
            font_size_int,
            .latin,
        );

        self.primary.bold_italic = try self.loadEmbeddedFont(
            embedded_fonts.jetbrains_mono_bold_italic,
            font_size_int,
            .latin,
        );

        log.info("Primary font family loaded (JetBrains Mono)", .{});
    }

    /// Load an embedded font
    fn loadEmbeddedFont(
        self: *FontCollection,
        data: []const u8,
        size_pixels: i32,
        coverage: FontFace.UnicodeRangeHint,
    ) !FontFace {
        var face = try self.library.initMemoryFace(data, 0);
        errdefer face.deinit();

        // Verify the face handle is valid
        if (@intFromPtr(face.handle) == 0) {
            face.deinit();
            return error.InvalidFontFace;
        }

        // Set char size: size_pixels * 64 for 26.6 fixed point format, 96 DPI
        try face.setCharSize(@intCast(size_pixels * 64), @intCast(size_pixels * 64), 96, 96);

        return FontFace{
            .face = face,
            .source = .{ .embedded = data },
            .coverage_hint = coverage,
        };
    }

    /// Load a system font file (deferred - only when needed)
    pub fn loadSystemFont(
        self: *FontCollection,
        path: []const u8,
        coverage: FontFace.UnicodeRangeHint,
    ) !FontFace {
        // Create null-terminated path
        var path_buf: [256]u8 = undefined;
        const path_z = try std.fmt.bufPrintZ(&path_buf, "{s}", .{path});

        var face = try self.library.initFace(path_z, 0);
        errdefer face.deinit();

        // Verify the face handle is valid
        if (@intFromPtr(face.handle) == 0) {
            face.deinit();
            return error.InvalidFontFace;
        }

        const font_size_px = self.font_size.toPixels();
        const size_pixels = @as(u32, @intFromFloat(@round(font_size_px)));
        // Set char size: size_pixels * 64 for 26.6 fixed point format, use font DPI
        const dpi = self.font_size.dpi; // Already a u16, no conversion needed
        const char_size = @as(i32, @intCast(size_pixels)) * 64;
        try face.setCharSize(char_size, char_size, dpi, dpi);

        log.info("Loaded system font: {s}", .{path});

        return FontFace{
            .face = face,
            .source = .{ .file_path = path },
            .coverage_hint = coverage,
        };
    }

    /// Load fallback fonts on-demand
    pub fn loadFallbackFonts(self: *FontCollection) !void {
        // Try to load Roboto Mono as first fallback (better Android coverage)
        if (self.tryLoadSystemFontFamily(
            AndroidFonts.roboto_mono,
            AndroidFonts.roboto_mono_bold,
            AndroidFonts.roboto_mono_italic,
            AndroidFonts.roboto_mono_bold_italic,
            .latin,
        )) |family| {
            try self.fallbacks.append(self.allocator, family);
            log.info("Loaded Roboto Mono as fallback", .{});
        }

        // Try to load CJK font for Asian scripts
        if (self.tryLoadSingleFont(AndroidFonts.noto_cjk, .cjk)) |family| {
            try self.fallbacks.append(self.allocator, family);
            log.info("Loaded Noto CJK as fallback", .{});
        }

        // Try to load emoji font
        if (self.tryLoadSingleFont(AndroidFonts.noto_emoji, .emoji)) |family| {
            try self.fallbacks.append(self.allocator, family);
            log.info("Loaded Noto Emoji as fallback", .{});
        }

        // Try DroidSans as final fallback
        if (self.tryLoadSystemFontPair(
            AndroidFonts.droid_sans,
            AndroidFonts.droid_sans_bold,
            .full,
        )) |family| {
            try self.fallbacks.append(self.allocator, family);
            log.info("Loaded DroidSans as final fallback", .{});
        }
    }

    /// Try to load a complete font family from system
    fn tryLoadSystemFontFamily(
        self: *FontCollection,
        regular_path: []const u8,
        bold_path: []const u8,
        italic_path: []const u8,
        bold_italic_path: []const u8,
        coverage: FontFace.UnicodeRangeHint,
    ) ?FontFamily {
        var family = FontFamily{};

        family.regular = self.loadSystemFont(regular_path, coverage) catch null;
        family.bold = self.loadSystemFont(bold_path, coverage) catch null;
        family.italic = self.loadSystemFont(italic_path, coverage) catch null;
        family.bold_italic = self.loadSystemFont(bold_italic_path, coverage) catch null;

        // Only return if at least regular was loaded
        if (family.regular) |_| {
            return family;
        }

        family.deinit();
        return null;
    }

    /// Try to load regular and bold variants
    fn tryLoadSystemFontPair(
        self: *FontCollection,
        regular_path: []const u8,
        bold_path: []const u8,
        coverage: FontFace.UnicodeRangeHint,
    ) ?FontFamily {
        var family = FontFamily{};

        family.regular = self.loadSystemFont(regular_path, coverage) catch null;
        family.bold = self.loadSystemFont(bold_path, coverage) catch null;

        if (family.regular) |_| {
            return family;
        }

        family.deinit();
        return null;
    }

    /// Try to load a single font (used for all styles)
    fn tryLoadSingleFont(
        self: *FontCollection,
        path: []const u8,
        coverage: FontFace.UnicodeRangeHint,
    ) ?FontFamily {
        const face = self.loadSystemFont(path, coverage) catch return null;

        return FontFamily{
            .regular = face,
            // Use same font for all styles
            .bold = null,
            .italic = null,
            .bold_italic = null,
        };
    }

    /// Find a font face that has a glyph for the given codepoint
    pub fn findFontForCodepoint(
        self: *FontCollection,
        codepoint: u21,
        style: FontStyle,
    ) ?*const FontFace {
        // Check primary font first
        if (self.primary.getFace(style)) |face| {
            if (face.hasGlyph(codepoint)) {
                return face;
            }
        }

        // Check fallback fonts
        for (self.fallbacks.items) |*family| {
            if (family.getFace(style)) |face| {
                if (face.hasGlyph(codepoint)) {
                    return face;
                }
            }
        }

        // No font found
        return null;
    }

    /// Get the primary font face for a style
    pub fn getPrimaryFace(self: *const FontCollection, style: FontStyle) ?*const FontFace {
        return self.primary.getFace(style);
    }
};