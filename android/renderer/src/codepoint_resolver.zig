//! Codepoint Resolver - resolves codepoints to fonts with caching
//!
//! This module implements the font fallback chain for resolving which font
//! should be used to render each codepoint, with caching for performance.
//! Follows Ghostty's CodepointResolver pattern.

const std = @import("std");
const FontCollection = @import("font_collection.zig").FontCollection;
const FontStyle = @import("font_collection.zig").FontStyle;
const FontFace = @import("font_collection.zig").FontFace;
const freetype = @import("freetype");

const log = std.log.scoped(.codepoint_resolver);

/// Result of codepoint resolution
pub const Resolution = struct {
    /// The font face to use for rendering
    face: *const FontFace,
    /// The glyph index in the font
    glyph_index: u32,
    /// Whether this required a fallback font
    is_fallback: bool,
};

/// Cache entry for resolved codepoints
const CacheEntry = struct {
    /// Index into primary (0) or fallback fonts array (1+)
    /// This avoids pointer invalidation issues
    font_index: u16,
    /// Style variant within the font family
    style: FontStyle,
    glyph_index: u32,
    is_fallback: bool,
};

/// Codepoint resolver with multi-level caching
pub const CodepointResolver = struct {
    allocator: std.mem.Allocator,
    collection: *FontCollection,

    /// Level 1 cache: (codepoint, style) -> font resolution
    /// Key is (codepoint << 2) | style
    cache: std.AutoHashMap(u32, CacheEntry),

    /// Whether fallback fonts have been loaded
    fallbacks_loaded: bool,

    /// Statistics for cache performance
    stats: struct {
        hits: usize = 0,
        misses: usize = 0,
        fallback_loads: usize = 0,
    } = .{},

    pub fn init(allocator: std.mem.Allocator, collection: *FontCollection) !CodepointResolver {
        return CodepointResolver{
            .allocator = allocator,
            .collection = collection,
            .cache = std.AutoHashMap(u32, CacheEntry).init(allocator),
            .fallbacks_loaded = false,
        };
    }

    pub fn deinit(self: *CodepointResolver) void {
        self.cache.deinit();
    }

    /// Clear the cache (e.g., after font changes)
    pub fn clearCache(self: *CodepointResolver) void {
        self.cache.clearRetainingCapacity();
        self.stats = .{};
    }

    /// Resolve a codepoint to a font face and glyph index
    pub fn resolve(
        self: *CodepointResolver,
        codepoint: u21,
        style: FontStyle,
    ) !?Resolution {
        // Create cache key
        const cache_key = (@as(u32, codepoint) << 2) | @intFromEnum(style);

        // Check cache first
        if (self.cache.get(cache_key)) |entry| {
            self.stats.hits += 1;

            // Get face from collection using cached indices
            const face: ?*const FontFace = if (entry.font_index == 0)
                self.collection.getPrimaryFace(entry.style)
            else blk: {
                const fallback_index = entry.font_index - 1;
                if (fallback_index < self.collection.fallbacks.items.len) {
                    const family = &self.collection.fallbacks.items[fallback_index];
                    break :blk family.getFace(entry.style);
                }
                break :blk null;
            };

            if (face) |f| {
                return Resolution{
                    .face = f,
                    .glyph_index = entry.glyph_index,
                    .is_fallback = entry.is_fallback,
                };
            } else {
                // Cached entry is stale, remove it and continue
                _ = self.cache.remove(cache_key);
            }
        }

        self.stats.misses += 1;

        // Log non-ASCII resolution attempts
        if (codepoint > 0x7F) {
            log.debug("Resolving non-ASCII U+{X:0>4} style={}", .{ codepoint, style });
        }

        // Try primary font first
        if (self.collection.getPrimaryFace(style)) |face| {
            // Safety check: ensure face handle is valid before calling getCharIndex
            // Double-check the handle is not null
            if (face.face.handle == null or @intFromPtr(face.face.handle) == 0) {
                log.err("Primary font face handle is null for style={}", .{style});
            } else {
                const glyph_index = face.face.getCharIndex(codepoint) orelse 0;
                if (glyph_index != 0) {
                    // Found in primary font
                    const resolution = Resolution{
                        .face = face,
                        .glyph_index = glyph_index,
                        .is_fallback = false,
                    };

                    // Cache the result with index
                    try self.cache.put(cache_key, CacheEntry{
                        .font_index = 0, // Primary font
                        .style = style,
                        .glyph_index = glyph_index,
                        .is_fallback = false,
                    });

                    if (codepoint > 0x7F) {
                        log.info("Found U+{X:0>4} in primary font (glyph={d})", .{ codepoint, glyph_index });
                    }

                    return resolution;
                }
            }
        }

        // Fallback fonts are loaded eagerly during FontCollection init
        // so we can use them directly

        // Try fallback fonts
        for (self.collection.fallbacks.items, 0..) |*family, fallback_idx| {
            if (family.getFace(style)) |face| {
                // Safety check: ensure face handle is valid before calling getCharIndex
                // Double-check the handle is not null
                if (face.face.handle == null or @intFromPtr(face.face.handle) == 0) {
                    log.err("Fallback font #{d} face handle is null for style={}", .{ fallback_idx, style });
                    continue;
                }

                const glyph_index = face.face.getCharIndex(codepoint) orelse 0;
                if (glyph_index != 0) {
                    const resolution = Resolution{
                        .face = face,
                        .glyph_index = glyph_index,
                        .is_fallback = true,
                    };

                    // Cache the result with fallback font index
                    try self.cache.put(cache_key, CacheEntry{
                        .font_index = @as(u16, @intCast(fallback_idx + 1)), // +1 because 0 is primary
                        .style = style,
                        .glyph_index = glyph_index,
                        .is_fallback = true,
                    });

                    log.info("Found U+{X:0>4} in fallback font #{d} (glyph={d})", .{ codepoint, fallback_idx, glyph_index });

                    return resolution;
                }
            }
        }

        // No font has this glyph - return null
        // Renderer should use a replacement character
        log.warn("No font found for U+{X:0>4} (will use replacement)", .{codepoint});
        return null;
    }

    /// Batch resolve multiple codepoints for efficiency
    pub fn resolveBatch(
        self: *CodepointResolver,
        codepoints: []const u21,
        style: FontStyle,
        results: []?Resolution,
    ) !void {
        std.debug.assert(codepoints.len == results.len);

        for (codepoints, results) |cp, *result| {
            result.* = try self.resolve(cp, style);
        }
    }

    /// Get cache statistics for debugging
    pub fn getCacheStats(self: *const CodepointResolver) void {
        const total = self.stats.hits + self.stats.misses;
        if (total > 0) {
            const hit_rate = @as(f32, @floatFromInt(self.stats.hits)) / @as(f32, @floatFromInt(total)) * 100.0;
            log.info("Cache stats: {d} hits, {d} misses ({d:.1}% hit rate), {d} fallback loads", .{
                self.stats.hits,
                self.stats.misses,
                hit_rate,
                self.stats.fallback_loads,
            });
        }
    }

    /// Pre-warm the cache with common codepoints
    pub fn prewarmCache(self: *CodepointResolver) !void {
        // ASCII range
        for (0x20..0x7F) |cp| {
            _ = try self.resolve(@intCast(cp), .regular);
        }

        // Common box drawing characters
        const box_chars = [_]u21{
            0x2500, 0x2502, 0x250C, 0x2510, 0x2514, 0x2518, // Basic box drawing
            0x251C, 0x2524, 0x252C, 0x2534, 0x253C, // Intersections
        };
        for (box_chars) |cp| {
            _ = try self.resolve(cp, .regular);
        }

        log.info("Cache prewarmed with common codepoints", .{});
    }
};

test "CodepointResolver basic functionality" {
    const testing = std.testing;
    const font_metrics = @import("font_metrics.zig");

    var collection = try FontCollection.init(
        testing.allocator,
        font_metrics.FontSize{ .points = 12, .dpi = 96 },
    );
    defer collection.deinit();

    var resolver = try CodepointResolver.init(testing.allocator, &collection);
    defer resolver.deinit();

    // ASCII should resolve to primary font
    if (try resolver.resolve('A', .regular)) |res| {
        try testing.expect(!res.is_fallback);
        try testing.expect(res.glyph_index != 0);
    }

    // Cache should work
    const before_hits = resolver.stats.hits;
    _ = try resolver.resolve('A', .regular);
    try testing.expect(resolver.stats.hits > before_hits);
}