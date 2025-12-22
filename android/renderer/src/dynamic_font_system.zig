//! Dynamic Font System - Integrated UTF-8 support with dynamic glyph loading
//!
//! This module integrates all the new UTF-8 components:
//! - FontCollection for multi-font management
//! - CodepointResolver for font fallback
//! - GlyphCache for rendered glyph caching
//! - AtlasSet for dynamic texture atlas management
//! - WidthCache for character width lookups

const std = @import("std");
const freetype = @import("freetype");
const FontCollection = @import("font_collection.zig").FontCollection;
const FontStyle = @import("font_collection.zig").FontStyle;
const CodepointResolver = @import("codepoint_resolver.zig").CodepointResolver;
const GlyphCache = @import("glyph_cache.zig").GlyphCache;
const AtlasSet = @import("atlas_packer.zig").AtlasSet;
const Atlas = @import("atlas_packer.zig").Atlas;
const WidthCache = @import("codepoint_width.zig").WidthCache;
const font_metrics = @import("font_metrics.zig");
const shaders = @import("shaders.zig");

const log = std.log.scoped(.dynamic_font_system);

/// Dynamic font system with full UTF-8 support
pub const DynamicFontSystem = struct {
    allocator: std.mem.Allocator,

    /// Font collection managing all fonts (heap-allocated for stable pointer)
    collection: *FontCollection,

    /// Resolver for codepoint → font mapping
    resolver: CodepointResolver,

    /// Cache for rendered glyphs
    glyph_cache: GlyphCache,

    /// Dynamic texture atlases
    atlas_set: AtlasSet,

    /// Cache for character widths
    width_cache: WidthCache,

    /// Font metrics
    metrics: font_metrics.FontMetrics,
    cell_width: u32,
    cell_height: u32,
    baseline: i32,

    /// Glyph lookup map: (codepoint, style) -> atlas location
    /// Key is (codepoint << 2) | style
    glyph_map: std.AutoHashMap(u32, GlyphLocation),

    /// Replacement character for missing glyphs
    const REPLACEMENT_CHAR: u21 = 0xFFFD; // �

    pub const GlyphLocation = struct {
        atlas_index: u32, // Which atlas (for multi-atlas)
        atlas_type: Atlas.Format, // Grayscale or RGBA
        x: u32, // Position in atlas
        y: u32,
        width: u32, // Glyph dimensions
        height: u32,
        bearing_x: i32, // Glyph metrics
        bearing_y: i32,
        advance: i32,
    };

    /// Initialize with specific font size
    pub fn init(allocator: std.mem.Allocator, font_size: font_metrics.FontSize) !DynamicFontSystem {
        log.info("Initializing dynamic font system with {d:.1}pt at {d} DPI", .{
            font_size.points,
            font_size.dpi
        });

        // Initialize components - heap-allocate collection for stable pointer
        const collection = try allocator.create(FontCollection);
        errdefer allocator.destroy(collection);
        collection.* = try FontCollection.init(allocator, font_size);
        errdefer collection.deinit();

        var resolver = try CodepointResolver.init(allocator, collection);
        errdefer resolver.deinit();

        var glyph_cache = try GlyphCache.init(allocator, 32); // 32 MB cache
        errdefer glyph_cache.deinit();

        var atlas_set = try AtlasSet.init(allocator, 2048, 2); // 2048x2048, 2px padding
        errdefer atlas_set.deinit();

        var width_cache = try WidthCache.init(allocator);
        errdefer width_cache.deinit();

        var glyph_map = std.AutoHashMap(u32, GlyphLocation).init(allocator);
        errdefer glyph_map.deinit();

        // Calculate font metrics from primary font
        var metrics: font_metrics.FontMetrics = undefined;
        var cell_width: u32 = undefined;
        var cell_height: u32 = undefined;
        var baseline: i32 = undefined;

        if (collection.getPrimaryFace(.regular)) |face| {
            const ft_face = face.face;
            const ft_metrics = ft_face.handle.*.size.*.metrics;

            // Convert from 26.6 fixed-point to float
            const ascent = @as(f32, @floatFromInt(ft_metrics.ascender)) / 64.0;
            const descent = @as(f32, @floatFromInt(ft_metrics.descender)) / 64.0;
            const line_gap = @as(f32, @floatFromInt(ft_metrics.height - (ft_metrics.ascender - ft_metrics.descender))) / 64.0;
            const max_advance = @as(f32, @floatFromInt(ft_metrics.max_advance)) / 64.0;

            metrics = .{
                .ascent = ascent,
                .descent = descent,
                .line_gap = line_gap,
                .cap_height = ascent * 0.8, // Estimate cap height
                .x_height = ascent * 0.5, // Estimate x-height
                .average_width = max_advance,
                .max_width = max_advance,
                .underline_position = 2.0, // 2 pixels below baseline
                .underline_thickness = 1.0, // 1 pixel thick
            };

            cell_width = @as(u32, @intFromFloat(@ceil(max_advance)));
            cell_height = @as(u32, @intFromFloat(@ceil(ascent - descent + line_gap)));
            baseline = @as(i32, @intFromFloat(@ceil(ascent)));
        } else {
            // Fallback metrics based on font size
            const font_px = font_size.toPixels();
            const line_height = font_px * 1.2; // Standard line height factor

            metrics = .{
                .ascent = font_px * 0.8,
                .descent = font_px * 0.2,
                .line_gap = font_px * 0.2,
                .cap_height = font_px * 0.7,
                .x_height = font_px * 0.5,
                .average_width = font_px * 0.6,
                .max_width = font_px * 0.6,
                .underline_position = 2.0,
                .underline_thickness = 1.0,
            };

            cell_width = @as(u32, @intFromFloat(@ceil(font_px * 0.6)));
            cell_height = @as(u32, @intFromFloat(@ceil(line_height)));
            baseline = @as(i32, @intFromFloat(@ceil(font_px * 0.8)));
        }

        const system = DynamicFontSystem{
            .allocator = allocator,
            .collection = collection,
            .resolver = resolver,
            .glyph_cache = glyph_cache,
            .atlas_set = atlas_set,
            .width_cache = width_cache,
            .metrics = metrics,
            .cell_width = cell_width,
            .cell_height = cell_height,
            .baseline = baseline,
            .glyph_map = glyph_map,
        };

        // TEMPORARY: Disable pre-warming to isolate crash
        // Pre-warm caches with common characters
        // try system.prewarmCaches();

        log.info("Dynamic font system initialized: cell {}x{}, baseline {} (pre-warming disabled)", .{
            cell_width, cell_height, baseline
        });

        return system;
    }

    /// Initialize with default font size
    pub fn initDefault(allocator: std.mem.Allocator, dpi: u16) !DynamicFontSystem {
        const font_size = font_metrics.FontSize.default(dpi);
        return try init(allocator, font_size);
    }

    pub fn deinit(self: *DynamicFontSystem) void {
        self.glyph_map.deinit();
        self.width_cache.deinit();
        self.atlas_set.deinit();
        self.glyph_cache.deinit();
        self.resolver.deinit();
        self.collection.deinit();
        self.allocator.destroy(self.collection);
    }

    /// Get glyph location for a codepoint
    pub fn getGlyphLocation(
        self: *DynamicFontSystem,
        codepoint: u21,
        style: FontStyle,
    ) !?GlyphLocation {
        // Check map first
        const key = (@as(u32, codepoint) << 2) | @intFromEnum(style);
        if (self.glyph_map.get(key)) |location| {
            return location;
        }

        // Resolve codepoint to font and glyph index
        const resolution = (try self.resolver.resolve(codepoint, style)) orelse {
            // No font has this glyph - try replacement character
            if (codepoint != REPLACEMENT_CHAR) {
                log.debug("No font for U+{X:0>4}, trying replacement char", .{codepoint});
                return self.getGlyphLocation(REPLACEMENT_CHAR, style) catch |err| {
                    log.warn("Failed to get replacement char: {}", .{err});
                    return null;
                };
            }
            log.debug("No font for replacement char U+{X:0>4}", .{REPLACEMENT_CHAR});
            return null;
        };

        // Get or render the glyph
        const font_size_px = self.collection.font_size.toPixels();
        const size_pixels = @as(u16, @intFromFloat(@round(font_size_px)));
        const rendered = try self.glyph_cache.getGlyph(
            resolution.face,
            resolution.glyph_index,
            size_pixels,
        );

        // Skip empty glyphs (spaces, etc)
        if (rendered.width == 0 or rendered.height == 0) {
            const location = GlyphLocation{
                .atlas_index = 0,
                .atlas_type = .grayscale,
                .x = 0,
                .y = 0,
                .width = 0,
                .height = 0,
                .bearing_x = rendered.bearing_x,
                .bearing_y = rendered.bearing_y,
                .advance = rendered.advance,
            };
            try self.glyph_map.put(key, location);
            return location;
        }

        // Pack into atlas
        const format: Atlas.Format = switch (rendered.format) {
            .grayscale => .grayscale,
            .rgba => .rgba,
        };

        const pack_result = try self.atlas_set.packGlyph(
            format,
            rendered.width,
            rendered.height,
            rendered.bitmap,
        );

        // Create location entry
        const location = GlyphLocation{
            .atlas_index = pack_result.atlas_index,
            .atlas_type = format,
            .x = pack_result.rect.x,
            .y = pack_result.rect.y,
            .width = pack_result.rect.width,
            .height = pack_result.rect.height,
            .bearing_x = rendered.bearing_x,
            .bearing_y = rendered.bearing_y,
            .advance = rendered.advance,
        };

        // Cache the location
        try self.glyph_map.put(key, location);

        return location;
    }

    /// Get character width
    pub fn getCharacterWidth(self: *DynamicFontSystem, codepoint: u21) u8 {
        return self.width_cache.get(codepoint);
    }

    /// Pre-warm caches with common characters
    fn prewarmCaches(self: *DynamicFontSystem) !void {
        log.info("Pre-warming font caches...", .{});

        // ASCII printable range
        for (0x20..0x7F) |cp| {
            // Handle errors gracefully during pre-warming
            _ = self.getGlyphLocation(@intCast(cp), .regular) catch |err| {
                log.debug("Failed to pre-warm U+{X:0>4}: {}", .{ cp, err });
                continue;
            };
        }

        // Common box drawing
        const box_chars = [_]u21{
            0x2500, 0x2502, 0x250C, 0x2510, 0x2514, 0x2518,
            0x251C, 0x2524, 0x252C, 0x2534, 0x253C,
        };
        for (box_chars) |cp| {
            // Handle errors gracefully during pre-warming
            _ = self.getGlyphLocation(cp, .regular) catch |err| {
                log.debug("Failed to pre-warm U+{X:0>4}: {}", .{ cp, err });
                continue;
            };
        }

        log.info("Font caches pre-warmed", .{});
    }

    /// Get cell size
    pub fn getCellSize(self: *const DynamicFontSystem) [2]f32 {
        return .{
            @floatFromInt(self.cell_width),
            @floatFromInt(self.cell_height),
        };
    }

    /// Get baseline offset
    pub fn getBaseline(self: *const DynamicFontSystem) f32 {
        return @floatFromInt(self.baseline);
    }

    /// Get required padding in pixels to prevent glyph clipping at viewport edges
    pub fn getViewportPadding(self: *const DynamicFontSystem) struct { right: u32, bottom: u32 } {
        // Conservative padding based on cell dimensions
        // This ensures glyphs have space for bearings and overhangs
        return .{
            .right = self.cell_width + (self.cell_width / 2), // 1.5x cell width
            .bottom = self.cell_height + (self.cell_height / 4), // 1.25x cell height
        };
    }

    /// Get grayscale atlas texture
    pub fn getGrayscaleAtlas(self: *const DynamicFontSystem, index: usize) ?u32 {
        if (index >= self.atlas_set.grayscale.items.len) return null;
        return self.atlas_set.grayscale.items[index].texture.texture.id;
    }

    /// Get RGBA atlas texture
    pub fn getRgbaAtlas(self: *const DynamicFontSystem, index: usize) ?u32 {
        if (index >= self.atlas_set.rgba.items.len) return null;
        return self.atlas_set.rgba.items[index].texture.texture.id;
    }

    /// Get atlas dimensions (width, height) as array
    pub fn getAtlasDimensions(self: *const DynamicFontSystem) [2]u32 {
        // Return dimensions of first grayscale atlas (they're all the same size)
        if (self.atlas_set.grayscale.items.len > 0) {
            const atlas = &self.atlas_set.grayscale.items[0];
            return .{ atlas.width, atlas.height };
        }
        // Default fallback
        return .{ 2048, 2048 };
    }

    /// Get atlas dimensions for shader uniforms
    pub fn getAtlasDimensionsUniform(self: *const DynamicFontSystem) shaders.AtlasDimensions {
        // Return dimensions of first grayscale atlas (they're all the same size)
        if (self.atlas_set.grayscale.items.len > 0) {
            const atlas = &self.atlas_set.grayscale.items[0];
            return .{
                .atlas_width = @floatFromInt(atlas.width),
                .atlas_height = @floatFromInt(atlas.height),
            };
        }
        // Default fallback
        return .{
            .atlas_width = 2048.0,
            .atlas_height = 2048.0,
        };
    }

    /// Get decoration metrics for text decorations (underlines, strikethrough)
    /// Returns relative positions (0.0 to 1.0 of cell height)
    pub fn getDecorationMetrics(self: *const DynamicFontSystem) [4]f32 {
        const cell_height_f = @as(f32, @floatFromInt(self.cell_height));
        const baseline_f = @as(f32, @floatFromInt(self.baseline));

        // Underline position: slightly below baseline
        const underline_pos = (baseline_f + 2.0) / cell_height_f;

        // Underline thickness: 2 pixels relative to cell height for better visibility
        const thickness = 2.0 / cell_height_f;

        // Strikethrough position: middle of x-height or 45% from top
        const strikethrough_pos = 0.45;

        return .{
            underline_pos,
            thickness,
            strikethrough_pos,
            thickness,
        };
    }

    /// Create CellText structure for rendering
    pub fn makeCellText(
        self: *DynamicFontSystem,
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

        // Get glyph location from dynamic font system
        const location = self.getGlyphLocation(codepoint, style) catch |err| {
            log.warn("Failed to get glyph location for U+{X:0>4}: {}", .{ codepoint, err });
            // Return empty glyph
            return shaders.CellText{
                .glyph_pos = .{ 0, 0 },
                .glyph_size = .{ 0, 0 },
                .bearings = .{ 0, 0 },
                .grid_pos = .{ grid_col, grid_row },
                .color = color,
                .atlas = .grayscale,
                .attributes = attributes,
            };
        } orelse {
            // No glyph available
            return shaders.CellText{
                .glyph_pos = .{ 0, 0 },
                .glyph_size = .{ 0, 0 },
                .bearings = .{ 0, 0 },
                .grid_pos = .{ grid_col, grid_row },
                .color = color,
                .atlas = .grayscale,
                .attributes = attributes,
            };
        };

        return shaders.CellText{
            .glyph_pos = .{ location.x, location.y },
            .glyph_size = .{ location.width, location.height },
            .bearings = .{ @as(i16, @intCast(location.bearing_x)), @as(i16, @intCast(location.bearing_y)) },
            .grid_pos = .{ grid_col, grid_row },
            .color = color,
            .atlas = .grayscale,
            .attributes = attributes,
        };
    }

    /// Print statistics
    pub fn printStats(self: *const DynamicFontSystem) void {
        self.resolver.getCacheStats();
        self.glyph_cache.getStats();

        log.info("Grayscale atlases: {}, RGBA atlases: {}", .{
            self.atlas_set.grayscale.items.len,
            self.atlas_set.rgba.items.len,
        });

        for (self.atlas_set.grayscale.items) |*atlas| {
            atlas.getStats();
        }
    }
};