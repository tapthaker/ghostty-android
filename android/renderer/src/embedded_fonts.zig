//! Embedded fonts for the Android renderer.
//!
//! Using @embedFile to compile fonts directly into the binary.
//! This simplifies deployment and eliminates the need for asset loading via JNI.

/// JetBrains Mono Regular - Main monospace font for terminal text
pub const jetbrains_mono_regular = @embedFile("JetBrainsMonoNoNF-Regular.ttf");

/// JetBrains Mono Bold - For bold text rendering
pub const jetbrains_mono_bold = @embedFile("JetBrainsMonoNerdFont-Bold.ttf");

/// JetBrains Mono Italic - For italic text rendering
pub const jetbrains_mono_italic = @embedFile("JetBrainsMonoNerdFont-Italic.ttf");

/// JetBrains Mono Bold Italic - For bold+italic text rendering
pub const jetbrains_mono_bold_italic = @embedFile("JetBrainsMonoNerdFont-BoldItalic.ttf");

/// OpenMoji Black - Monochrome outline emoji font
/// License: CC BY-SA 4.0
/// Source: https://github.com/hfg-gmuend/openmoji
/// Note: Using monochrome version because CBDT color emoji requires libpng
pub const openmoji_black = @embedFile("OpenMoji-Black.ttf");
