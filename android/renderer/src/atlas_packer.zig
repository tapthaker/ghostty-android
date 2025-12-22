//! Atlas Packer - Dynamic texture atlas management with bin packing
//!
//! This module implements a shelf-based bin packing algorithm for efficiently
//! packing glyphs into texture atlases, following Ghostty's approach.

const std = @import("std");
const gl = @import("gl_es.zig");
const Texture = @import("texture.zig");

const log = std.log.scoped(.atlas_packer);

/// Rectangle in the atlas
pub const Rect = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,

    pub fn area(self: Rect) u32 {
        return self.width * self.height;
    }

    pub fn contains(self: Rect, other: Rect) bool {
        return other.x >= self.x and
            other.y >= self.y and
            other.x + other.width <= self.x + self.width and
            other.y + other.height <= self.y + self.height;
    }
};

/// A shelf in the atlas (for shelf packing algorithm)
const Shelf = struct {
    y: u32, // Y position of the shelf
    height: u32, // Height of the shelf
    width_used: u32, // Current width used in this shelf
};

/// Dynamic texture atlas with bin packing
pub const Atlas = struct {
    allocator: std.mem.Allocator,
    texture: Texture,
    width: u32,
    height: u32,
    format: Format,

    /// Padding between glyphs (to prevent bleeding)
    padding: u32,

    /// Current shelves for packing
    shelves: std.ArrayList(Shelf),

    /// Next available Y position for new shelf
    next_shelf_y: u32,

    /// Statistics
    stats: struct {
        glyphs_packed: usize = 0,
        pixels_used: usize = 0,
        shelf_count: usize = 0,
    } = .{},

    pub const Format = enum {
        grayscale, // R8 for regular text
        rgba, // RGBA8 for color emoji
    };

    /// Initialize a new atlas
    pub fn init(
        allocator: std.mem.Allocator,
        width: u32,
        height: u32,
        format: Format,
        padding: u32,
    ) !Atlas {
        // Create texture based on format
        const opts = Texture.Options{
            .format = switch (format) {
                .grayscale => .red,
                .rgba => .rgba,
            },
            .internal_format = switch (format) {
                .grayscale => .r8,
                .rgba => .rgba8,
            },
            .min_filter = .linear,
            .mag_filter = .linear,
            .wrap_s = .clamp_to_edge,
            .wrap_t = .clamp_to_edge,
        };
        const texture = try Texture.init(opts, width, height, null);

        // Clear texture to transparent
        const clear_size = width * height * switch (format) {
            .grayscale => @as(usize, 1),
            .rgba => @as(usize, 4),
        };
        const clear_data = try allocator.alloc(u8, clear_size);
        defer allocator.free(clear_data);
        @memset(clear_data, 0);

        texture.texture.bind(.texture_2d);
        gl.c.glTexSubImage2D(
            gl.c.GL_TEXTURE_2D,
            0,
            0,
            0,
            @intCast(width),
            @intCast(height),
            switch (format) {
                .grayscale => gl.c.GL_RED,
                .rgba => gl.c.GL_RGBA,
            },
            gl.c.GL_UNSIGNED_BYTE,
            clear_data.ptr,
        );

        return Atlas{
            .allocator = allocator,
            .texture = texture,
            .width = width,
            .height = height,
            .format = format,
            .padding = padding,
            .shelves = try std.ArrayList(Shelf).initCapacity(allocator, 0),
            .next_shelf_y = padding, // Start with padding from top
        };
    }

    pub fn deinit(self: *Atlas) void {
        self.texture.deinit();
        self.shelves.deinit(self.allocator);
    }

    /// Pack a glyph into the atlas
    pub fn packGlyph(
        self: *Atlas,
        glyph_width: u32,
        glyph_height: u32,
        bitmap_data: []const u8,
    ) !?Rect {
        // Add padding to dimensions
        const padded_width = glyph_width + self.padding * 2;
        const padded_height = glyph_height + self.padding * 2;

        // Find a shelf that can fit this glyph
        for (self.shelves.items) |*shelf| {
            if (shelf.height >= padded_height) {
                const remaining_width = self.width - shelf.width_used;
                if (remaining_width >= padded_width) {
                    // Found a shelf with space
                    const rect = Rect{
                        .x = shelf.width_used + self.padding,
                        .y = shelf.y + self.padding,
                        .width = glyph_width,
                        .height = glyph_height,
                    };

                    // Update shelf
                    shelf.width_used += padded_width;

                    // Upload glyph to texture
                    self.uploadGlyph(rect, bitmap_data);

                    self.stats.glyphs_packed += 1;
                    self.stats.pixels_used += padded_width * padded_height;

                    return rect;
                }
            }
        }

        // No existing shelf fits - create a new one
        if (self.next_shelf_y + padded_height <= self.height) {
            const shelf = Shelf{
                .y = self.next_shelf_y,
                .height = padded_height,
                .width_used = padded_width,
            };

            try self.shelves.append(self.allocator, shelf);
            self.next_shelf_y += padded_height;
            self.stats.shelf_count += 1;

            const rect = Rect{
                .x = self.padding,
                .y = shelf.y + self.padding,
                .width = glyph_width,
                .height = glyph_height,
            };

            // Upload glyph to texture
            self.uploadGlyph(rect, bitmap_data);

            self.stats.glyphs_packed += 1;
            self.stats.pixels_used += padded_width * padded_height;

            return rect;
        }

        // Atlas is full
        log.warn("Atlas full: cannot pack glyph of size {}x{}", .{ glyph_width, glyph_height });
        return null;
    }

    /// Upload glyph bitmap to texture
    fn uploadGlyph(self: *Atlas, rect: Rect, bitmap_data: []const u8) void {
        self.texture.texture.bind(.texture_2d);

        const gl_format = @as(c_uint, switch (self.format) {
            .grayscale => gl.c.GL_RED,
            .rgba => gl.c.GL_RGBA,
        });

        gl.c.glTexSubImage2D(
            gl.c.GL_TEXTURE_2D,
            0,
            @intCast(rect.x),
            @intCast(rect.y),
            @intCast(rect.width),
            @intCast(rect.height),
            gl_format,
            gl.c.GL_UNSIGNED_BYTE,
            bitmap_data.ptr,
        );
    }

    /// Clear the atlas (for reuse)
    pub fn clear(self: *Atlas) !void {
        self.shelves.clearRetainingCapacity();
        self.next_shelf_y = self.padding;
        self.stats = .{};

        // Clear texture
        const clear_size = self.width * self.height * switch (self.format) {
            .grayscale => @as(usize, 1),
            .rgba => @as(usize, 4),
        };
        const clear_data = try self.allocator.alloc(u8, clear_size);
        defer self.allocator.free(clear_data);
        @memset(clear_data, 0);

        self.texture.texture.bind(.texture_2d);
        gl.c.glTexSubImage2D(
            gl.c.GL_TEXTURE_2D,
            0,
            0,
            0,
            @intCast(self.width),
            @intCast(self.height),
            switch (self.format) {
                .grayscale => gl.c.GL_RED,
                .rgba => gl.c.GL_RGBA,
            },
            gl.c.GL_UNSIGNED_BYTE,
            clear_data.ptr,
        );
    }

    /// Get atlas statistics
    pub fn getStats(self: *const Atlas) void {
        const total_pixels = self.width * self.height;
        const usage = @as(f32, @floatFromInt(self.stats.pixels_used)) / @as(f32, @floatFromInt(total_pixels)) * 100.0;
        log.info("Atlas {}x{}: {} glyphs, {} shelves, {d:.1}% usage", .{
            self.width,
            self.height,
            self.stats.glyphs_packed,
            self.stats.shelf_count,
            usage,
        });
    }
};

/// Atlas set managing multiple atlases
pub const AtlasSet = struct {
    allocator: std.mem.Allocator,

    /// Grayscale atlas for regular text
    grayscale: std.ArrayList(Atlas),
    /// RGBA atlas for color emoji
    rgba: std.ArrayList(Atlas),

    /// Default atlas size
    default_size: u32,
    /// Padding between glyphs
    padding: u32,

    pub fn init(allocator: std.mem.Allocator, default_size: u32, padding: u32) !AtlasSet {
        var set = AtlasSet{
            .allocator = allocator,
            .grayscale = try std.ArrayList(Atlas).initCapacity(allocator, 1),
            .rgba = try std.ArrayList(Atlas).initCapacity(allocator, 1),
            .default_size = default_size,
            .padding = padding,
        };

        // Create initial atlases
        try set.grayscale.append(allocator, try Atlas.init(allocator, default_size, default_size, .grayscale, padding));
        try set.rgba.append(allocator, try Atlas.init(allocator, default_size, default_size, .rgba, padding));

        return set;
    }

    pub fn deinit(self: *AtlasSet) void {
        for (self.grayscale.items) |*atlas| {
            atlas.deinit();
        }
        self.grayscale.deinit(self.allocator);

        for (self.rgba.items) |*atlas| {
            atlas.deinit();
        }
        self.rgba.deinit(self.allocator);
    }

    /// Pack a glyph, creating new atlases as needed
    pub fn packGlyph(
        self: *AtlasSet,
        format: Atlas.Format,
        width: u32,
        height: u32,
        bitmap_data: []const u8,
    ) !struct { atlas_index: u32, rect: Rect } {
        const atlases = switch (format) {
            .grayscale => &self.grayscale,
            .rgba => &self.rgba,
        };

        // Try existing atlases
        for (atlases.items, 0..) |*atlas, i| {
            if (try atlas.packGlyph(width, height, bitmap_data)) |rect| {
                return .{ .atlas_index = @intCast(i), .rect = rect };
            }
        }

        // Create new atlas
        log.info("Creating new {} atlas", .{format});
        var new_atlas = try Atlas.init(
            self.allocator,
            self.default_size,
            self.default_size,
            format,
            self.padding,
        );

        // Pack in new atlas
        const rect = (try new_atlas.packGlyph(width, height, bitmap_data)) orelse {
            new_atlas.deinit();
            return error.GlyphTooLarge;
        };

        const index = atlases.items.len;
        try atlases.append(self.allocator, new_atlas);

        return .{ .atlas_index = @intCast(index), .rect = rect };
    }
};