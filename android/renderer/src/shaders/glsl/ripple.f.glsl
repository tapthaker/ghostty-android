#include "common.glsl"

// Ripple effect fragment shader
// Renders an expanding ring effect for touch feedback

layout(location = 0) out vec4 out_FragColor;

void main() {
    // Early exit if ripple is not active
    if (ripple_progress <= 0.0 || ripple_max_radius <= 0.0) {
        discard;
    }

    // Get fragment position in screen coordinates
    // gl_FragCoord.y is flipped (0 at bottom), so we flip it to match touch coords
    vec2 fragCoord = gl_FragCoord.xy;
    fragCoord.y = screen_size.y - fragCoord.y;

    // Calculate distance from ripple center
    float dist = distance(fragCoord, ripple_center);

    // Current radius based on progress
    float currentRadius = ripple_max_radius * ripple_progress;

    // Ring effect: visible near the edge of the expanding circle
    float ringWidth = 100.0;
    float innerRadius = max(0.0, currentRadius - ringWidth);

    // Smooth edges using smoothstep
    float outerAlpha = 1.0 - smoothstep(currentRadius - 4.0, currentRadius, dist);
    float innerAlpha = smoothstep(innerRadius, innerRadius + ringWidth * 0.6, dist);
    float ringAlpha = outerAlpha * innerAlpha;

    // Fade out as progress increases (faster fade)
    float fadeAlpha = 1.0 - (ripple_progress * ripple_progress);

    // Accent color: Light Blue 500 (#03A9F4)
    vec3 rippleColor = vec3(0.012, 0.663, 0.957);

    // Combine alphas
    float alpha = ringAlpha * fadeAlpha * 0.35;

    // Discard nearly transparent pixels for performance
    if (alpha < 0.005) {
        discard;
    }

    // Premultiplied alpha output
    out_FragColor = vec4(rippleColor * alpha, alpha);
}
