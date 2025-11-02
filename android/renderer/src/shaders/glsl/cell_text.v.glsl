#include "common.glsl"

// The position of the glyph in the texture (x, y)
layout(location = 0) in uvec2 glyph_pos;

// The size of the glyph in the texture (w, h)
layout(location = 1) in uvec2 glyph_size;

// The left and top bearings for the glyph (x, y)
layout(location = 2) in ivec2 bearings;

// The grid coordinates (x, y) where x < columns and y < rows
layout(location = 3) in uvec2 grid_pos;

// The color of the rendered text glyph.
layout(location = 4) in uvec4 color;

// Which atlas this glyph is in.
layout(location = 5) in uint atlas;

// Misc glyph properties.
layout(location = 6) in uint glyph_bools;

// Values `atlas` can take.
const uint ATLAS_GRAYSCALE = 0u;
const uint ATLAS_COLOR = 1u;

// Masks for the `glyph_bools` attribute
const uint NO_MIN_CONTRAST = 1u;
const uint IS_CURSOR_GLYPH = 2u;

// Output variables (individual variables instead of interface block for ES compatibility)
flat out uint out_atlas;
flat out vec4 out_color;
flat out vec4 out_bg_color;
out vec2 out_tex_coord; // Pixel coordinates - will be normalized in fragment shader

// NOTE: SSBOs are not supported in vertex shaders on Mali-G57 (max = 0)
// We'll use the global background color instead of per-cell colors for now
// layout(binding = 1, std430) buffer bg_cells {
//     uint bg_colors[];
// };

void main() {
    uvec2 grid_size = unpack2u16(grid_size_packed_2u16);
    uvec2 cursor_pos = unpack2u16(cursor_pos_packed_2u16);
    bool cursor_wide = (bools & CURSOR_WIDE) != 0u;
    bool use_linear_blending = (bools & USE_LINEAR_BLENDING) != 0u;

    // Convert the grid x, y into world space x, y by accounting for cell size
    vec2 cell_pos = cell_size * vec2(grid_pos);

    int vid = gl_VertexID;

    // We use a triangle strip with 4 vertices to render quads,
    // so we determine which corner of the cell this vertex is in
    // based on the vertex ID.
    //
    //   0 --> 1
    //   |   .'|
    //   |  /  |
    //   | L   |
    //   2 --> 3
    //
    // 0 = top-left  (0, 0)
    // 1 = top-right (1, 0)
    // 2 = bot-left  (0, 1)
    // 3 = bot-right (1, 1)
    vec2 corner;
    corner.x = float(vid == 1 || vid == 3);
    corner.y = float(vid == 2 || vid == 3);

    out_atlas = atlas;

    //              === Grid Cell ===
    //      +X
    // 0,0--...->
    //   |
    //   . offset.x = bearings.x
    // +Y.               .|.
    //   .               | |
    //   |   cell_pos -> +-------+   _.
    //   v             ._|       |_. _|- offset.y = cell_size.y - bearings.y
    //                 | | .###. | |
    //                 | | #...# | |
    //   glyph_size.y -+ | ##### | |
    //                 | | #.... | +- bearings.y
    //                 |_| .#### | |
    //                   |       |_|
    //                   +-------+
    //                     |_._|
    //                       |
    //                  glyph_size.x
    //
    // In order to get the top left of the glyph, we compute an offset based on
    // the bearings. The Y bearing is the distance from the bottom of the cell
    // to the top of the glyph, so we subtract it from the cell height to get
    // the y offset. The X bearing is the distance from the left of the cell
    // to the left of the glyph, so it works as the x offset directly.

    vec2 size = vec2(glyph_size);
    vec2 offset = vec2(bearings);

    offset.y = cell_size.y - offset.y;

    // Calculate the final position of the cell which uses our glyph size
    // and glyph offset to create the correct bounding box for the glyph.
    cell_pos = cell_pos + size * corner + offset;
    gl_Position = projection_matrix * vec4(cell_pos.x, cell_pos.y, 0.0, 1.0);

    // Calculate the texture coordinate in pixels. This is NOT normalized
    // (between 0.0 and 1.0), and does not need to be, since it will be
    // normalized in the fragment shader using texture size.
    out_tex_coord = vec2(glyph_pos) + vec2(glyph_size) * corner;

    // Get our color. We always fetch a linearized version to
    // make it easier to handle minimum contrast calculations.
    out_color = load_color(color, true);

    // Use global background color (per-cell bg colors require SSBO in vertex shader,
    // which is not supported on Mali-G57)
    out_bg_color = load_color(unpack4u8(bg_color_packed_4u8), true);

    // If we have a minimum contrast, we need to check if we need to
    // change the color of the text to ensure it has enough contrast
    // with the background.
    if (min_contrast > 1.0 && (glyph_bools & NO_MIN_CONTRAST) == 0u) {
        // Ensure our minimum contrast
        out_color = contrasted_color(min_contrast, out_color, out_bg_color);
    }

    // Check if current position is under cursor (including wide cursor)
    bool is_cursor_pos = ((grid_pos.x == cursor_pos.x) || (cursor_wide && (grid_pos.x == (cursor_pos.x + 1u)))) && (grid_pos.y == cursor_pos.y);

    // If this cell is the cursor cell, but we're not processing
    // the cursor glyph itself, then we need to change the color.
    if ((glyph_bools & IS_CURSOR_GLYPH) == 0u && is_cursor_pos) {
        out_color = load_color(unpack4u8(cursor_color_packed_4u8), use_linear_blending);
    }
}
