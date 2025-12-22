//! Glyph Cache - Multi-tier caching for rendered glyphs
//!
//! This module implements a three-level cache following Ghostty's architecture:
//! 1. Codepoint → Glyph Index (handled by CodepointResolver)
//! 2. Glyph Index → Rendered Glyph
//! 3. Text Run → Shaped Output (for complex text with HarfBuzz)

const std = @import("std");
const freetype = @import("freetype");
const FontFace = @import("font_collection.zig").FontFace;
const FontStyle = @import("font_collection.zig").FontStyle;

const log = std.log.scoped(.glyph_cache);

/// Rendered glyph data ready for atlas packing
pub const RenderedGlyph = struct {
    /// Bitmap data (grayscale or RGBA)
    bitmap: []u8,
    /// Width in pixels
    width: u32,
    /// Height in pixels
    height: u32,
    /// Format of the bitmap
    format: Format,
    /// Horizontal bearing (offset from origin to left edge)
    bearing_x: i32,
    /// Vertical bearing (offset from baseline to top edge)
    bearing_y: i32,
    /// Horizontal advance to next glyph
    advance: i32,

    pub const Format = enum {
        grayscale, // 1 byte per pixel
        rgba, // 4 bytes per pixel (for color emoji)
    };

    pub fn deinit(self: *RenderedGlyph, allocator: std.mem.Allocator) void {
        allocator.free(self.bitmap);
    }
};

/// Atlas entry for a cached glyph
pub const AtlasEntry = struct {
    /// Position in atlas texture
    atlas_x: u32,
    atlas_y: u32,
    /// Size in atlas
    width: u32,
    height: u32,
    /// Which atlas texture (for multi-atlas support)
    atlas_index: u32,
    /// Glyph metrics
    bearing_x: i32,
    bearing_y: i32,
    advance: i32,
};

/// Key for the glyph cache
const GlyphKey = struct {
    /// Font face pointer (as usize for hashing)
    face_ptr: usize,
    /// Glyph index in the font
    glyph_index: u32,
    /// Rendering size (for multi-size support)
    size_pixels: u16,

    pub fn hash(self: GlyphKey) u64 {
        var h = std.hash.Wyhash.init(0);
        h.update(std.mem.asBytes(&self.face_ptr));
        h.update(std.mem.asBytes(&self.glyph_index));
        h.update(std.mem.asBytes(&self.size_pixels));
        return h.final();
    }
};

/// LRU cache for rendered glyphs
pub const GlyphCache = struct {
    allocator: std.mem.Allocator,

    /// Map from glyph key to cache entry
    entries: std.AutoHashMap(u64, CacheNode),

    /// LRU list for eviction (key-based, safe across HashMap reallocation)
    lru_head_key: ?u64,
    lru_tail_key: ?u64,

    /// Maximum cache size in bytes
    max_size: usize,
    /// Current cache size in bytes
    current_size: usize,

    /// Statistics
    stats: struct {
        hits: usize = 0,
        misses: usize = 0,
        evictions: usize = 0,
        renders: usize = 0,
    } = .{},

    const CacheNode = struct {
        key: u64,
        glyph: RenderedGlyph,
        atlas_entry: ?AtlasEntry, // Set when added to atlas
        size_bytes: usize,
        prev_key: ?u64,  // Key-based linking (safe across HashMap reallocation)
        next_key: ?u64,
    };

    pub fn init(allocator: std.mem.Allocator, max_size_mb: usize) !GlyphCache {
        return GlyphCache{
            .allocator = allocator,
            .entries = std.AutoHashMap(u64, CacheNode).init(allocator),
            .lru_head_key = null,
            .lru_tail_key = null,
            .max_size = max_size_mb * 1024 * 1024,
            .current_size = 0,
        };
    }

    pub fn deinit(self: *GlyphCache) void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.glyph.deinit(self.allocator);
        }
        self.entries.deinit();
    }

    /// Get or render a glyph
    pub fn getGlyph(
        self: *GlyphCache,
        face: *const FontFace,
        glyph_index: u32,
        size_pixels: u16,
    ) !*RenderedGlyph {
        const key = GlyphKey{
            .face_ptr = @intFromPtr(face),
            .glyph_index = glyph_index,
            .size_pixels = size_pixels,
        };
        const key_hash = key.hash();

        // Check cache
        if (self.entries.getPtr(key_hash)) |node| {
            self.stats.hits += 1;
            self.moveToFront(key_hash);
            return &node.glyph;
        }

        self.stats.misses += 1;

        // Render the glyph
        const glyph = try self.renderGlyph(face, glyph_index, size_pixels);
        self.stats.renders += 1;

        // Calculate size
        const size_bytes = glyph.bitmap.len + @sizeOf(RenderedGlyph);

        // Evict if necessary
        while (self.current_size + size_bytes > self.max_size) {
            if (!self.evictLRU()) break;
        }

        // Add to cache (key-based linking)
        const node = CacheNode{
            .key = key_hash,
            .glyph = glyph,
            .atlas_entry = null,
            .size_bytes = size_bytes,
            .prev_key = null,
            .next_key = self.lru_head_key,
        };

        try self.entries.put(key_hash, node);

        // Update LRU list (key-based)
        if (self.lru_head_key) |head_key| {
            if (self.entries.getPtr(head_key)) |head| {
                head.prev_key = key_hash;
            }
        }
        self.lru_head_key = key_hash;
        if (self.lru_tail_key == null) {
            self.lru_tail_key = key_hash;
        }

        self.current_size += size_bytes;

        // Get pointer after all HashMap operations are done
        const entry = self.entries.getPtr(key_hash).?;
        return &entry.glyph;
    }

    /// Render a glyph using FreeType
    fn renderGlyph(
        self: *GlyphCache,
        face: *const FontFace,
        glyph_index: u32,
        size_pixels: u16,
    ) !RenderedGlyph {
        // Set size (may already be set)
        // Use 26.6 fixed point format (multiply by 64), assume 96 DPI
        const char_size: i32 = @as(i32, @intCast(size_pixels)) * 64;
        try face.face.setCharSize(char_size, char_size, 96, 96);

        // Load and render the glyph
        try face.face.loadGlyph(glyph_index, .{ .render = true });

        // Access glyph slot through handle
        const glyph = face.face.handle.*.glyph;
        const bitmap = &glyph.*.bitmap;

        // Determine format based on bitmap mode
        // FreeType pixel modes: FT_PIXEL_MODE_GRAY = 2, FT_PIXEL_MODE_BGRA = 6
        const format: RenderedGlyph.Format = switch (bitmap.pixel_mode) {
            2 => .grayscale, // FT_PIXEL_MODE_GRAY
            6 => .rgba,      // FT_PIXEL_MODE_BGRA
            else => .grayscale, // Default to grayscale
        };

        // Calculate bitmap size
        const bitmap_size = bitmap.width * bitmap.rows * switch (format) {
            .grayscale => @as(usize, 1),
            .rgba => @as(usize, 4),
        };

        // Copy bitmap data
        const bitmap_data = try self.allocator.alloc(u8, bitmap_size);
        if (bitmap.buffer) |buffer| {
            @memcpy(bitmap_data, buffer[0..bitmap_size]);
        } else {
            // Empty glyph (space, etc)
            @memset(bitmap_data, 0);
        }

        return RenderedGlyph{
            .bitmap = bitmap_data,
            .width = bitmap.width,
            .height = bitmap.rows,
            .format = format,
            .bearing_x = glyph.*.bitmap_left,
            .bearing_y = glyph.*.bitmap_top,
            .advance = @intCast(glyph.*.advance.x >> 6), // Convert from 26.6 fixed point
        };
    }

    /// Move a node to the front of the LRU list (key-based)
    fn moveToFront(self: *GlyphCache, node_key: u64) void {
        if (self.lru_head_key == node_key) return; // Already at front

        const node = self.entries.getPtr(node_key) orelse return;

        // Remove from current position
        if (node.prev_key) |prev_key| {
            if (self.entries.getPtr(prev_key)) |prev| {
                prev.next_key = node.next_key;
            }
        }
        if (node.next_key) |next_key| {
            if (self.entries.getPtr(next_key)) |next| {
                next.prev_key = node.prev_key;
            }
        }
        if (self.lru_tail_key == node_key) {
            self.lru_tail_key = node.prev_key;
        }

        // Move to front
        node.prev_key = null;
        node.next_key = self.lru_head_key;
        if (self.lru_head_key) |head_key| {
            if (self.entries.getPtr(head_key)) |head| {
                head.prev_key = node_key;
            }
        }
        self.lru_head_key = node_key;
    }

    /// Evict the least recently used entry (key-based)
    fn evictLRU(self: *GlyphCache) bool {
        const tail_key = self.lru_tail_key orelse return false;
        const tail = self.entries.getPtr(tail_key) orelse return false;

        // Get info before removing
        const size_bytes = tail.size_bytes;
        const prev_key = tail.prev_key;

        // Update LRU list pointers
        if (prev_key) |pk| {
            if (self.entries.getPtr(pk)) |prev| {
                prev.next_key = null;
            }
            self.lru_tail_key = pk;
        } else {
            self.lru_head_key = null;
            self.lru_tail_key = null;
        }

        // Free glyph data and remove from map
        tail.glyph.deinit(self.allocator);
        _ = self.entries.remove(tail_key);
        self.current_size -= size_bytes;
        self.stats.evictions += 1;

        return true;
    }

    /// Get cache statistics
    pub fn getStats(self: *const GlyphCache) void {
        const total = self.stats.hits + self.stats.misses;
        if (total > 0) {
            const hit_rate = @as(f32, @floatFromInt(self.stats.hits)) / @as(f32, @floatFromInt(total)) * 100.0;
            log.info("Glyph cache: {d} hits, {d} misses ({d:.1}% hit rate), {d} renders, {d} evictions", .{
                self.stats.hits,
                self.stats.misses,
                hit_rate,
                self.stats.renders,
                self.stats.evictions,
            });
            log.info("Cache size: {d:.1} MB / {d:.1} MB", .{
                @as(f32, @floatFromInt(self.current_size)) / 1024.0 / 1024.0,
                @as(f32, @floatFromInt(self.max_size)) / 1024.0 / 1024.0,
            });
        }
    }
};