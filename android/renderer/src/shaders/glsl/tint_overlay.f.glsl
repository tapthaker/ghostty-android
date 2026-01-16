#include "common.glsl"

// Tint overlay fragment shader
// Renders a thin colored accent line at the top edge for session differentiation.
// Clean, minimal, and follows HIG patterns used by VS Code, iTerm2, Windows Terminal.
// Uses the full-screen triangle from full_screen.v.glsl

layout(location = 0) out vec4 out_FragColor;

// Accent line thickness in pixels (must match ACCENT_LINE_HEIGHT in renderer.zig)
const float ACCENT_THICKNESS = 3.0;

void main() {
    // Skip rendering if tint is disabled
    if (tint_alpha <= 0.0) {
        discard;
    }

    // Get fragment position in screen coordinates
    vec2 fragCoord = gl_FragCoord.xy;

    // Calculate distance from top edge (Y is flipped in GL, so top is screen_size.y)
    float distFromTop = screen_size.y - fragCoord.y;

    // Only render within the accent line thickness at top edge
    if (distFromTop > ACCENT_THICKNESS) {
        discard;
    }

    bool use_linear_blending = (bools & USE_LINEAR_BLENDING) != 0u;

    // Unpack Android ARGB color (0xAARRGGBB format)
    // unpack4u8 returns bytes in order: [B, G, R, A] due to little-endian
    uvec4 packed = unpack4u8(tint_color_packed_4u8);
    uvec4 argb_to_rgba = uvec4(packed.z, packed.y, packed.x, packed.w); // R, G, B, A

    // Normalize to 0.0-1.0 range
    vec4 tintColor = vec4(argb_to_rgba) / 255.0;

    // Linearize if needed for linear blending
    if (use_linear_blending) {
        tintColor = linearize(tintColor);
    }

    // Apply tint alpha (color's own alpha * user-specified alpha)
    float finalAlpha = tintColor.a * tint_alpha;

    // Output with PREMULTIPLIED alpha (required for GL_ONE, GL_ONE_MINUS_SRC_ALPHA blending)
    out_FragColor = vec4(tintColor.rgb * finalAlpha, finalAlpha);
}
