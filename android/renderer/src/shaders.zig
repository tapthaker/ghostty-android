///! Shader definitions, uniforms, and vertex attribute structures
///!
///! This module defines all the data structures used to communicate with
///! the GLSL shaders, including the global uniforms buffer and per-instance
///! vertex attributes for each rendering pipeline.

const std = @import("std");

/// The global uniforms that are passed to all shaders via UBO binding point 1.
/// This MUST match the layout in shaders/glsl/common.glsl.
///
/// Note: All alignment values are for std140 layout in GLSL uniform blocks.
pub const Uniforms = extern struct {
    /// The projection matrix for turning world coordinates to normalized.
    /// This is calculated based on the size of the screen.
    projection_matrix: [16]f32 align(16),

    /// Size of the screen (render target) in pixels.
    screen_size: [2]f32 align(8),

    /// Size of a single cell in pixels, unscaled.
    cell_size: [2]f32 align(8),

    /// Size of the grid in columns and rows (packed as 2x u16).
    grid_size_packed_2u16: u32 align(4),

    /// The padding around the terminal grid in pixels. In order:
    /// top, right, bottom, left.
    grid_padding: [4]f32 align(16),

    /// Bit mask defining which directions to extend cell colors into the padding.
    /// Order, LSB first: left, right, up, down
    padding_extend: PaddingExtend align(4),

    /// The minimum contrast ratio for text. The contrast ratio is calculated
    /// according to the WCAG 2.0 spec.
    min_contrast: f32 align(4),

    /// The cursor position (packed as 2x u16).
    cursor_pos_packed_2u16: u32 align(4),

    /// The cursor color (RGBA, 4x u8 packed into u32).
    cursor_color_packed_4u8: u32 align(4),

    /// The background color for the whole surface (RGBA, 4x u8 packed into u32).
    bg_color_packed_4u8: u32 align(4),

    /// Various booleans, in a packed struct for space efficiency.
    bools: Bools align(4),

    pub const Bools = packed struct(u32) {
        /// Whether the cursor is 2 cells wide.
        cursor_wide: bool,

        /// Indicates that colors provided to the shader are already in
        /// the P3 color space, so they don't need to be converted from sRGB.
        use_display_p3: bool,

        /// Indicates that the color attachments for the shaders have
        /// an `*_srgb` pixel format, which means the shaders need to
        /// output linear RGB colors rather than gamma encoded colors.
        use_linear_blending: bool,

        /// Enables a weight correction step that makes text rendered
        /// with linear alpha blending have a similar apparent weight
        /// (thickness) to gamma-incorrect blending.
        use_linear_correction: bool,

        _padding: u28 = 0,
    };

    pub const PaddingExtend = packed struct(u32) {
        left: bool = false,
        right: bool = false,
        up: bool = false,
        down: bool = false,
        _padding: u28 = 0,
    };

    /// Helper to pack two u16 values into a single u32
    pub fn pack2u16(a: u16, b: u16) u32 {
        return (@as(u32, a) << 0) | (@as(u32, b) << 16);
    }

    /// Helper to pack four u8 values (RGBA) into a single u32
    pub fn pack4u8(r: u8, g: u8, b: u8, a: u8) u32 {
        return (@as(u32, r) << 0) |
            (@as(u32, g) << 8) |
            (@as(u32, b) << 16) |
            (@as(u32, a) << 24);
    }
};

/// Atlas dimensions uniform buffer (UBO binding point 2).
/// Used by cell_text fragment shader to normalize texture coordinates.
pub const AtlasDimensions = extern struct {
    grayscale_size: [2]f32 align(8),
    color_size: [2]f32 align(8),
};

/// Vertex attributes for the cell_text shader (text rendering).
/// This is a single parameter for instanced rendering of text glyphs.
pub const CellText = extern struct {
    glyph_pos: [2]u32 align(8) = .{ 0, 0 },
    glyph_size: [2]u32 align(8) = .{ 0, 0 },
    bearings: [2]i16 align(4) = .{ 0, 0 },
    grid_pos: [2]u16 align(4),
    color: [4]u8 align(4),
    atlas: Atlas align(1),
    bools: packed struct(u8) {
        no_min_contrast: bool = false,
        is_cursor_glyph: bool = false,
        _padding: u6 = 0,
    } align(1) = .{},
    attributes: Attributes align(2) = .{},

    pub const Atlas = enum(u8) {
        grayscale = 0,
        color = 1,
    };

    pub const Attributes = packed struct(u16) {
        bold: bool = false,
        italic: bool = false,
        dim: bool = false,
        strikethrough: bool = false,
        underline: Underline = .none,
        inverse: bool = false,
        _padding: u8 = 0,

        pub const Underline = enum(u3) {
            none = 0,
            single = 1,
            double = 2,
            curly = 3,
            dotted = 4,
            dashed = 5,
        };
    };

    comptime {
        // Verify size matches what we expect for optimal packing
        std.debug.assert(@sizeOf(CellText) == 32);
    }
};

/// Vertex attributes for the cell_bg shader (cell background colors).
/// Note: This is passed via SSBO, not per-instance attributes.
pub const CellBg = [4]u8;

/// Vertex attributes for the image shader (terminal images / Kitty protocol).
pub const Image = extern struct {
    grid_pos: [2]f32 align(8),
    cell_offset: [2]f32 align(8),
    source_rect: [4]f32 align(16),
    dest_size: [2]f32 align(8),
};

/// Vertex attributes for the bg_image shader (background image).
pub const BgImage = extern struct {
    opacity: f32 align(4),
    info: Info align(1),

    pub const Info = packed struct(u8) {
        position: Position,
        fit: Fit,
        repeat: bool,
        _padding: u1 = 0,

        pub const Position = enum(u4) {
            tl = 0, // top-left
            tc = 1, // top-center
            tr = 2, // top-right
            ml = 3, // middle-left
            mc = 4, // middle-center
            mr = 5, // middle-right
            bl = 6, // bottom-left
            bc = 7, // bottom-center
            br = 8, // bottom-right
        };

        pub const Fit = enum(u2) {
            contain = 0,
            cover = 1,
            stretch = 2,
            none = 3,
        };
    };
};

/// Create an orthographic projection matrix for 2D rendering.
/// This maps screen coordinates (0,0 at top-left, width/height at bottom-right)
/// to normalized device coordinates (-1,-1 to 1,1).
pub fn createOrthoMatrix(width: f32, height: f32) [16]f32 {
    // Column-major order for GLSL
    return .{
        2.0 / width,  0.0,           0.0, 0.0,
        0.0,          -2.0 / height, 0.0, 0.0,
        0.0,          0.0,           1.0, 0.0,
        -1.0,         1.0,           0.0, 1.0,
    };
}
