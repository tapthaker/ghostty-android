#include "common.glsl"

// Sweep effect fragment shader
// Renders a horizontal bar that sweeps across the screen for gesture feedback

layout(location = 0) out vec4 out_FragColor;

// Sweep direction constants
const uint SWEEP_NONE = 0u;
const uint SWEEP_UP = 1u;
const uint SWEEP_DOWN = 2u;

void main() {
    // Early exit if sweep is not active
    if (sweep_direction == SWEEP_NONE || sweep_progress <= 0.0) {
        discard;
    }

    // Get fragment position in screen coordinates
    // gl_FragCoord.y is 0 at bottom in OpenGL, flip to match screen coords
    vec2 fragCoord = gl_FragCoord.xy;
    float screenY = screen_size.y - fragCoord.y;

    // Calculate sweep bar position based on direction and progress
    // Bar thickness in pixels
    float barThickness = 60.0;
    float barCenter;

    if (sweep_direction == SWEEP_UP) {
        // Sweep from bottom to top
        // At progress 0: bar is at bottom (screen_size.y)
        // At progress 1: bar is at top (0)
        barCenter = screen_size.y * (1.0 - sweep_progress);
    } else {
        // Sweep from top to bottom
        // At progress 0: bar is at top (0)
        // At progress 1: bar is at bottom (screen_size.y)
        barCenter = screen_size.y * sweep_progress;
    }

    // Calculate distance from bar center
    float dist = abs(screenY - barCenter);

    // Create bar shape with soft edges
    float halfThickness = barThickness * 0.5;
    float edgeSoftness = 20.0;

    // Smooth falloff from center
    float barAlpha = 1.0 - smoothstep(halfThickness - edgeSoftness, halfThickness, dist);

    // Fade out as progress increases (faster towards the end)
    float fadeAlpha = 1.0 - (sweep_progress * sweep_progress);

    // Accent color: Light Blue 500 (#03A9F4) - same as ripple
    vec3 sweepColor = vec3(0.012, 0.663, 0.957);

    // Combine alphas
    float alpha = barAlpha * fadeAlpha * 0.4;

    // Discard nearly transparent pixels for performance
    if (alpha < 0.005) {
        discard;
    }

    // Premultiplied alpha output
    out_FragColor = vec4(sweepColor * alpha, alpha);
}
