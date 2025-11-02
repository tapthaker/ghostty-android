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

in CellTextVertexOut {
    flat uint atlas;
    flat vec4 color;
    flat vec4 bg_color;
    vec2 tex_coord;  // Pixel coordinates from vertex shader
} in_data;

// Values `atlas` can take.
const uint ATLAS_GRAYSCALE = 0u;
const uint ATLAS_COLOR = 1u;

// Must declare this output for some versions of OpenGL.
layout(location = 0) out vec4 out_FragColor;

void main() {
    bool use_linear_blending = (bools & USE_LINEAR_BLENDING) != 0u;
    bool use_linear_correction = (bools & USE_LINEAR_CORRECTION) != 0u;

    switch (in_data.atlas) {
        default:
        case ATLAS_GRAYSCALE:
        {
            // Our input color is always linear.
            vec4 color = in_data.color;

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
            vec2 normalized_coord = in_data.tex_coord / grayscale_size;

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
                vec4 bg = in_data.bg_color;
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

            out_FragColor = color;
            return;
        }

        case ATLAS_COLOR:
        {
            // Normalize pixel coordinates to 0.0-1.0 range for sampler2D
            vec2 normalized_coord = in_data.tex_coord / color_size;

            // For now, we assume that color glyphs
            // are already premultiplied linear colors.
            vec4 color = texture(atlas_color, normalized_coord);

            // If we are doing linear blending, we can return this right away.
            if (use_linear_blending) {
                out_FragColor = color;
                return;
            }

            // Otherwise we need to unlinearize the color. Since the alpha is
            // premultiplied, we need to divide it out before unlinearizing.
            color.rgb /= vec3(color.a);
            color = unlinearize(color);
            color.rgb *= vec3(color.a);

            out_FragColor = color;
            return;
        }
    }
}
