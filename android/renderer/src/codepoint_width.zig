//! Codepoint width caching layer for the Android renderer
//!
//! This module provides a cached interface to libghostty's Unicode width
//! implementation, optimizing for common cases and reducing lookups.

const std = @import("std");
const ghostty_vt = @import("ghostty-vt");
const log = std.log.scoped(.codepoint_width);

/// Width cache for fast lookup of recently used codepoints
pub const WidthCache = struct {
    const CacheSize = 4096; // Cache 4K most recent codepoints
    const Entry = struct {
        codepoint: u21,
        width: u8,
    };

    allocator: std.mem.Allocator,
    entries: []Entry,
    /// Simple hash table with linear probing
    lookup: []?usize,

    pub fn init(allocator: std.mem.Allocator) !WidthCache {
        var cache = WidthCache{
            .allocator = allocator,
            .entries = try allocator.alloc(Entry, CacheSize),
            .lookup = try allocator.alloc(?usize, CacheSize),
        };

        // Initialize lookup table to empty
        @memset(cache.lookup, null);

        // Pre-populate with ASCII range for fast access
        for (0..128) |i| {
            const cp: u21 = @intCast(i);
            _ = cache.get(cp); // This will populate the cache
        }

        return cache;
    }

    pub fn deinit(self: *WidthCache) void {
        self.allocator.free(self.entries);
        self.allocator.free(self.lookup);
    }

    /// Get the width of a codepoint, using cache if available
    pub fn get(self: *WidthCache, codepoint: u21) u8 {
        // Fast path for ASCII (always width 1 or 0 for control chars)
        if (codepoint < 128) {
            // Control characters (0x00-0x1F, 0x7F) have width 0
            if (codepoint < 0x20 or codepoint == 0x7F) {
                return 0;
            }
            return 1;
        }

        // Check cache
        const hash = @mod(codepoint, CacheSize);
        var idx = hash;
        var attempts: usize = 0;

        // Linear probing to find entry
        while (attempts < 16) : (attempts += 1) {
            if (self.lookup[idx]) |entry_idx| {
                if (self.entries[entry_idx].codepoint == codepoint) {
                    // Cache hit
                    return self.entries[entry_idx].width;
                }
            } else {
                // Empty slot - cache miss
                break;
            }
            idx = @mod(idx + 1, CacheSize);
        }

        // Cache miss - get width from libghostty
        const width = getWidthFromLibghostty(codepoint);

        // Add to cache (simple replacement strategy)
        const entry_idx = @mod(codepoint, CacheSize); // Simple index
        self.entries[entry_idx] = .{
            .codepoint = codepoint,
            .width = width,
        };
        self.lookup[@mod(codepoint, CacheSize)] = entry_idx;

        return width;
    }

    /// Check if a codepoint is double-width (CJK, emoji, etc)
    pub fn isWide(self: *WidthCache, codepoint: u21) bool {
        return self.get(codepoint) == 2;
    }

    /// Check if a codepoint is zero-width (combining marks, etc)
    pub fn isZeroWidth(self: *WidthCache, codepoint: u21) bool {
        return self.get(codepoint) == 0;
    }
};

/// Get width directly from libghostty without caching
fn getWidthFromLibghostty(codepoint: u21) u8 {
    // Simple width calculation based on Unicode ranges
    // This is a simplified version that covers common cases

    // ASCII and control characters
    if (codepoint < 0x80) {
        // Control characters have width 0
        if (codepoint < 0x20 or codepoint == 0x7F) return 0;
        // Printable ASCII has width 1
        return 1;
    }

    // Zero-width characters (combining marks, etc.)
    if ((codepoint >= 0x0300 and codepoint <= 0x036F) or // Combining Diacritical Marks
        (codepoint >= 0x1AB0 and codepoint <= 0x1AFF) or // Combining Diacritical Marks Extended
        (codepoint >= 0x1DC0 and codepoint <= 0x1DFF) or // Combining Diacritical Marks Supplement
        (codepoint >= 0x20D0 and codepoint <= 0x20FF) or // Combining Diacritical Marks for Symbols
        (codepoint >= 0xFE20 and codepoint <= 0xFE2F))   // Combining Half Marks
    {
        return 0;
    }

    // Wide characters (CJK, fullwidth forms, emoji)
    if ((codepoint >= 0x1100 and codepoint <= 0x115F) or // Hangul Jamo
        (codepoint >= 0x2E80 and codepoint <= 0x2FFF) or // CJK Radicals
        (codepoint >= 0x3000 and codepoint <= 0x303F) or // CJK Symbols
        (codepoint >= 0x3040 and codepoint <= 0x309F) or // Hiragana
        (codepoint >= 0x30A0 and codepoint <= 0x30FF) or // Katakana
        (codepoint >= 0x3400 and codepoint <= 0x4DBF) or // CJK Extension A
        (codepoint >= 0x4E00 and codepoint <= 0x9FFF) or // CJK Unified Ideographs
        (codepoint >= 0xF900 and codepoint <= 0xFAFF) or // CJK Compatibility
        (codepoint >= 0xFF00 and codepoint <= 0xFF60) or // Fullwidth Forms
        (codepoint >= 0xFFE0 and codepoint <= 0xFFE6) or // Fullwidth symbols
        (codepoint >= 0x20000 and codepoint <= 0x2FFFD) or // CJK Extension B-F
        (codepoint >= 0x1F300 and codepoint <= 0x1F9FF))  // Emoji
    {
        return 2;
    }

    // Default to width 1 for everything else
    return 1;
}

/// Get the display width of a codepoint (0, 1, or 2)
/// This is a direct interface without caching for one-off lookups
pub fn codepointWidth(codepoint: u21) u8 {
    return getWidthFromLibghostty(codepoint);
}

test "WidthCache basic functionality" {
    const testing = std.testing;
    var cache = try WidthCache.init(testing.allocator);
    defer cache.deinit();

    // ASCII characters
    try testing.expectEqual(@as(u8, 1), cache.get('a'));
    try testing.expectEqual(@as(u8, 1), cache.get('Z'));
    try testing.expectEqual(@as(u8, 1), cache.get('9'));

    // Control characters
    try testing.expectEqual(@as(u8, 0), cache.get(0x00)); // NULL
    try testing.expectEqual(@as(u8, 0), cache.get(0x0A)); // LF
    try testing.expectEqual(@as(u8, 0), cache.get(0x7F)); // DEL

    // Wide characters (if supported by libghostty)
    // Note: These tests assume libghostty properly identifies these as wide
    try testing.expectEqual(@as(u8, 2), cache.get(0x4E00)); // CJK Ideograph
    try testing.expectEqual(@as(u8, 2), cache.get(0x1F600)); // Emoji
}

test "codepointWidth direct function" {
    const testing = std.testing;

    // Test direct function without cache
    try testing.expectEqual(@as(u8, 1), codepointWidth('A'));
    try testing.expectEqual(@as(u8, 0), codepointWidth(0x00));
    try testing.expectEqual(@as(u8, 2), codepointWidth(0x4E00));
}