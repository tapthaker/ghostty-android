#include "common.glsl"

// OpenGL ES uses sampler2D instead of sampler2DRect
// Texture coordinates must be normalized (0.0 to 1.0)
// Note: OpenGL ES 3.1 doesn't support layout(binding) for samplers
// These must be bound programmatically using glUniform1i
uniform sampler2D atlas_grayscale;
uniform sampler2D atlas_color;

// Texture dimensions for coordinate normalization
// These will be set as uniforms
layout(binding = 2, std140) uniform AtlasDimensions {
    vec2 grayscale_size;  // Width and height of grayscale atlas
    vec2 color_size;      // Width and height of color atlas
};

// Input variables (individual variables instead of interface block for ES compatibility)
// These must match the vertex shader output names exactly
flat in uint out_atlas;
flat in vec4 out_color;
flat in vec4 out_bg_color;
in vec2 out_tex_coord;  // Pixel coordinates from vertex shader
flat in uint out_attributes; // Text attributes
in vec2 out_cell_coord; // Position within cell (0.0-1.0)
flat in vec4 out_glyph_bounds; // Glyph bounds within cell (x_start, y_start, x_end, y_end)
flat in uvec2 out_glyph_pos; // Glyph position in atlas
flat in uvec2 out_glyph_size; // Glyph size in atlas

// Values `atlas` can take.
const uint ATLAS_GRAYSCALE = 0u;
const uint ATLAS_COLOR = 1u;

// Attribute masks (must match vertex shader)
const uint ATTR_BOLD = 1u;
const uint ATTR_ITALIC = 2u;
const uint ATTR_DIM = 4u;
const uint ATTR_STRIKETHROUGH = 8u;
const uint ATTR_UNDERLINE_MASK = 112u;
const uint ATTR_UNDERLINE_SHIFT = 4u;
const uint ATTR_INVERSE = 128u;

// Underline types
const uint UNDERLINE_NONE = 0u;
const uint UNDERLINE_SINGLE = 1u;
const uint UNDERLINE_DOUBLE = 2u;
const uint UNDERLINE_CURLY = 3u;
const uint UNDERLINE_DOTTED = 4u;
const uint UNDERLINE_DASHED = 5u;

// Must declare this output for some versions of OpenGL.
layout(location = 0) out vec4 out_FragColor;

// Check if we should draw underline at this pixel
bool isUnderline(uint underline_type, vec2 cell_coord) {
    if (underline_type == UNDERLINE_NONE) return false;

    float y = cell_coord.y;
    float line_thickness = 0.04; // 4% of cell height (thinner line)
    float underline_pos = 0.88;  // Position at 88% down the cell

    if (underline_type == UNDERLINE_SINGLE) {
        return (y >= underline_pos && y <= underline_pos + line_thickness);
    } else if (underline_type == UNDERLINE_DOUBLE) {
        float line1_pos = 0.82;
        float line2_pos = 0.92;
        return (y >= line1_pos && y <= line1_pos + line_thickness) ||
               (y >= line2_pos && y <= line2_pos + line_thickness);
    } else if (underline_type == UNDERLINE_DOTTED) {
        if (y < underline_pos || y > underline_pos + line_thickness) return false;
        // Create dotted pattern based on x coordinate
        float dot_period = 0.15; // Dots every 15% of cell width
        float x_mod = mod(cell_coord.x, dot_period);
        return x_mod < dot_period * 0.4; // Dot is 40% of period
    } else if (underline_type == UNDERLINE_DASHED) {
        if (y < underline_pos || y > underline_pos + line_thickness) return false;
        // Create dashed pattern
        float dash_period = 0.25;
        float x_mod = mod(cell_coord.x, dash_period);
        return x_mod < dash_period * 0.6; // Dash is 60% of period
    } else if (underline_type == UNDERLINE_CURLY) {
        // Simplified curly underline as wavy line
        float wave_y = underline_pos + sin(cell_coord.x * 20.0) * 0.03;
        return (y >= wave_y && y <= wave_y + line_thickness);
    }
    return false;
}

// Check if we should draw strikethrough at this pixel
bool isStrikethrough(vec2 cell_coord) {
    float y = cell_coord.y;
    float line_thickness = 0.04; // 4% of cell height (thinner line)
    float strike_pos = 0.52; // Slightly above center for better alignment with text
    return (y >= strike_pos && y <= strike_pos + line_thickness);
}

void main() {
    bool use_linear_blending = (bools & USE_LINEAR_BLENDING) != 0u;
    bool use_linear_correction = (bools & USE_LINEAR_CORRECTION) != 0u;

    // Extract attribute flags first
    // TESTING: Disable inverse video
    bool is_inverse = false; // (out_attributes & ATTR_INVERSE) != 0u;

    // Swap colors for inverse video BEFORE rendering
    vec4 fg_color = is_inverse ? out_bg_color : out_color;
    vec4 bg_color = is_inverse ? out_color : out_bg_color;

    // Check if current pixel is within glyph bounds
    bool in_glyph = (out_cell_coord.x >= out_glyph_bounds.x && out_cell_coord.x <= out_glyph_bounds.z &&
                     out_cell_coord.y >= out_glyph_bounds.y && out_cell_coord.y <= out_glyph_bounds.w);

    vec4 final_color;

    // DEBUG MODE: Visualize glyph bounds and coordinates
    // Uncomment to enable debug visualization
    // if (in_glyph) {
    //     // Green: inside glyph bounds
    //     out_FragColor = vec4(0.0, 1.0, 0.0, 1.0);
    // } else {
    //     // Red: outside glyph bounds
    //     out_FragColor = vec4(1.0, 0.0, 0.0, 1.0);
    // }
    // // Visualize cell coordinates as colors
    // out_FragColor = vec4(out_cell_coord.x, out_cell_coord.y, 0.0, 1.0);
    // // Visualize glyph bounds
    // out_FragColor = vec4(out_glyph_bounds.x, out_glyph_bounds.y, out_glyph_bounds.z, 1.0);
    // return;

    // Only sample texture if we're within the glyph bounds
    if (in_glyph) {
        // Calculate the correct texture coordinate based on position within glyph
        // Map our position within the cell to position within the glyph, then to atlas coords
        vec2 glyph_local_coord = (out_cell_coord - out_glyph_bounds.xy) / (out_glyph_bounds.zw - out_glyph_bounds.xy);
        vec2 tex_coord = vec2(out_glyph_pos) + glyph_local_coord * vec2(out_glyph_size);

        switch (out_atlas) {
            case ATLAS_GRAYSCALE:
            {
                // Our input color is always linear.
                vec4 color = fg_color;

                // If we're not doing linear blending, then we need to
                // re-apply the gamma encoding to our color manually.
                //
                // Since the alpha is premultiplied, we need to divide
                // it out before unlinearizing and re-multiply it after.
                if (!use_linear_blending) {
                    color.rgb /= vec3(color.a);
                    color = unlinearize(color);
                    color.rgb *= vec3(color.a);
                }

                // Normalize pixel coordinates to 0.0-1.0 range for sampler2D
                vec2 normalized_coord = tex_coord / grayscale_size;

                // Fetch our alpha mask for this pixel.
                float a = texture(atlas_grayscale, normalized_coord).r;

                // Linear blending weight correction corrects the alpha value to
                // produce blending results which match gamma-incorrect blending.
                if (use_linear_correction) {
                    // Short explanation of how this works:
                    //
                    // We get the luminances of the foreground and background colors,
                    // and then unlinearize them and perform blending on them. This
                    // gives us our desired luminance, which we derive our new alpha
                    // value from by mapping the range [bg_l, fg_l] to [0, 1], since
                    // our final blend will be a linear interpolation from bg to fg.
                    //
                    // This yields virtually identical results for grayscale blending,
                    // and very similar but non-identical results for color blending.
                    vec4 bg = bg_color;
                    float fg_l = luminance(color.rgb);
                    float bg_l = luminance(bg.rgb);
                    // To avoid numbers going haywire, we don't apply correction
                    // when the bg and fg luminances are within 0.001 of each other.
                    if (abs(fg_l - bg_l) > 0.001) {
                        float blend_l = linearize(unlinearize(fg_l) * a + unlinearize(bg_l) * (1.0 - a));
                        a = clamp((blend_l - bg_l) / (fg_l - bg_l), 0.0, 1.0);
                    }
                }

                // Multiply our whole color by the alpha mask.
                // Since we use premultiplied alpha, this is
                // the correct way to apply the mask.
                color *= a;

                final_color = color;
                break;
            }

            case ATLAS_COLOR:
            {
                // Normalize pixel coordinates to 0.0-1.0 range for sampler2D
                vec2 normalized_coord = tex_coord / color_size;

                // For now, we assume that color glyphs
                // are already premultiplied linear colors.
                vec4 color = texture(atlas_color, normalized_coord);

                // If we are doing linear blending, we can use this right away.
                if (!use_linear_blending) {
                    // Otherwise we need to unlinearize the color. Since the alpha is
                    // premultiplied, we need to divide it out before unlinearizing.
                    color.rgb /= vec3(color.a);
                    color = unlinearize(color);
                    color.rgb *= vec3(color.a);
                }

                final_color = color;
                break;
            }

            default:
                final_color = vec4(1.0, 0.0, 1.0, 1.0); // Magenta for error
                break;
        }
    } else {
        // Outside glyph bounds - render transparent (or background for inverse)
        if (is_inverse) {
            // For inverse video, fill with background color
            final_color = bg_color;
        } else {
            // Transparent
            final_color = vec4(0.0, 0.0, 0.0, 0.0);
        }
    }

    // Apply remaining text attributes
    bool is_dim = (out_attributes & ATTR_DIM) != 0u;
    // TESTING: Disable strikethrough
    bool is_strikethrough = false; // (out_attributes & ATTR_STRIKETHROUGH) != 0u;
    // TESTING: Disable underline
    uint underline_type = 0u; // (out_attributes & ATTR_UNDERLINE_MASK) >> ATTR_UNDERLINE_SHIFT;

    // Apply dim (reduce brightness by 50%)
    if (is_dim) {
        final_color.rgb *= 0.5;
    }

    // Bold and italic are now handled by using actual bold/italic glyphs from the atlas
    // No need for synthetic brightness adjustment

    // Check if we should draw underline or strikethrough
    // TESTING: Disable ALL decorations (underline, strikethrough, reverse video)
    bool draw_underline = false; // isUnderline(underline_type, out_cell_coord);
    bool draw_strikethrough = false; // is_strikethrough && isStrikethrough(out_cell_coord);

    // Draw underline or strikethrough by setting full opacity at those pixels
    if (draw_underline || draw_strikethrough) {
        final_color = fg_color; // Use foreground color for lines (respects inverse)
    }

    out_FragColor = final_color;
}
