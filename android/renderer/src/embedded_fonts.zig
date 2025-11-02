//! Embedded fonts for the Android renderer.
//!
//! Using @embedFile to compile fonts directly into the binary.
//! This simplifies deployment and eliminates the need for asset loading via JNI.

/// JetBrains Mono Regular - Main monospace font for terminal text
pub const jetbrains_mono_regular = @embedFile("JetBrainsMonoNoNF-Regular.ttf");
