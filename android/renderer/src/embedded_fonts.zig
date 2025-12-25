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

/// Twemoji Mozilla - Color emoji font using COLR/CPAL format
/// License: CC BY 4.0 (Twitter emoji) + MIT (Mozilla font build)
/// Source: https://github.com/mozilla/twemoji-colr
/// Note: COLR/CPAL format works with FreeType without libpng (unlike CBDT)
pub const twemoji_colr = @embedFile("Twemoji-Mozilla.ttf");

/// Noto Sans Symbols 2 - Extended symbols including media control characters
/// License: OFL 1.1
/// Source: https://github.com/googlefonts/noto-fonts
/// Contains: U+23F4-23F5 (play triangles), U+23CE (return symbol), etc.
pub const noto_sans_symbols2 = @embedFile("NotoSansSymbols2-Regular.ttf");
