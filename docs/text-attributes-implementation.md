# Text Attributes Implementation - UPDATED

## Overview

This document describes the **COMPLETE IMPLEMENTATION** of terminal text attributes in the Ghostty Android renderer. All standard text attributes are fully functional.

## Current Implementation Status

### ✅ Fully Implemented (All Working!)

- **Bold** - Uses actual bold font face (`JetBrainsMonoNerdFont-Bold.ttf`)
- **Italic** - Uses actual italic font face (`JetBrainsMonoNerdFont-Italic.ttf`)
- **Bold+Italic** - Uses actual bold-italic font face (`JetBrainsMonoNerdFont-BoldItalic.ttf`)
- **Underline** (5 types: single, double, dotted, dashed, curly) - Procedural rendering
- **Strikethrough** - Procedural horizontal line rendering
- **Dim** - 50% brightness reduction
- **Inverse/Reverse Video** - Foreground/background color swap with proper fill

## Architecture

### Data Flow Pipeline

```
VT Terminal Style Flags
        ↓
screen_extractor.zig (extracts from terminal)
    - Maps VT style flags to CellData attributes
    - Lines 116-136: Full attribute extraction
        ↓
renderer.zig (converts to GPU format)
    - Lines 631-639: Creates packed attributes
    - Calls font_system.makeCellText()
        ↓
font_system.zig (selects font face)
    - Lines 494-502: Selects correct font variant
    - Returns CellText with proper atlas position
        ↓
Vertex Shader (cell_text.v.glsl)
    - Lines 121-159: Expands quad for decorations
    - Passes attributes to fragment shader
        ↓
Fragment Shader (cell_text.f.glsl)
    - Lines 103-105: Handles inverse video
    - Lines 54-94: Renders decorations
    - Lines 233-248: Applies dim effect
```

### Key Components

#### 1. Font System (`font_system.zig`)

The font system maintains **4 separate FreeType font faces**:

```zig
// Lines 36-40 in font_system.zig
face: freetype.Face,              // Regular font
face_bold: freetype.Face,         // Bold font
face_italic: freetype.Face,       // Italic font
face_bold_italic: freetype.Face,  // Bold+Italic font
```

Font files are embedded at compile time:
- `JetBrainsMonoNerdFont-Regular.ttf` (default, already included)
- `JetBrainsMonoNerdFont-Bold.ttf`
- `JetBrainsMonoNerdFont-Italic.ttf`
- `JetBrainsMonoNerdFont-BoldItalic.ttf`

#### 2. Style Selection Logic

```zig
// Lines 494-502 in font_system.zig
const style: FontStyle = if (attributes.bold and attributes.italic)
    .bold_italic
else if (attributes.bold)
    .bold
else if (attributes.italic)
    .italic
else
    .regular;
```

#### 3. Attribute Packing (`shaders.zig`)

Attributes are efficiently packed into 16 bits:

```zig
// Lines 122-129 in shaders.zig
pub const Attributes = packed struct(u16) {
    bold: bool = false,           // bit 0
    italic: bool = false,          // bit 1
    dim: bool = false,             // bit 2
    strikethrough: bool = false,  // bit 3
    underline: Underline = .none, // bits 4-6 (enum, 3 bits)
    inverse: bool = false,         // bit 7
    _padding: u8 = 0,              // bits 8-15 (unused)
};
```

#### 4. Vertex Shader Quad Expansion

For decorations (underline, strikethrough, inverse), the vertex shader expands the quad:

```glsl
// Lines 121-159 in cell_text.v.glsl
bool expand_to_cell = has_underline || has_strikethrough || has_inverse;

if (expand_to_cell) {
    // Store original glyph bounds for fragment shader
    out_glyph_bounds = vec4(glyph_start.x, glyph_start.y, glyph_end.x, glyph_end.y);

    // Expand quad to cover entire cell
    size = cell_size;
    offset = vec2(0.0, 0.0);
} else {
    // Normal glyph-sized quad
    out_glyph_bounds = vec4(0.0, 0.0, 1.0, 1.0);
}
```

#### 5. Fragment Shader Decoration Rendering

The fragment shader procedurally generates decorations:

```glsl
// Underline rendering (lines 54-86 in cell_text.f.glsl)
bool isUnderline(uint underline_type, vec2 cell_coord) {
    float y = cell_coord.y;
    float line_thickness = 0.04; // 4% of cell height
    float underline_pos = 0.88;  // 88% down the cell

    if (underline_type == UNDERLINE_SINGLE) {
        return (y >= underline_pos && y <= underline_pos + line_thickness);
    } else if (underline_type == UNDERLINE_DOUBLE) {
        // Two lines at 82% and 92%
    } else if (underline_type == UNDERLINE_DOTTED) {
        // Dots with 15% period, 40% fill
    } else if (underline_type == UNDERLINE_DASHED) {
        // Dashes with 25% period, 60% fill
    } else if (underline_type == UNDERLINE_CURLY) {
        // Sine wave pattern
    }
}

// Strikethrough (lines 88-94)
bool isStrikethrough(vec2 cell_coord) {
    float strike_pos = 0.52; // 52% down (slightly above center)
    return (y >= strike_pos && y <= strike_pos + line_thickness);
}
```

## How Text Attributes Work Together

1. **Bold + Underline**: Uses bold font face AND draws underline
2. **Italic + Strikethrough**: Uses italic font face AND draws strikethrough
3. **Inverse + Bold**: Swaps colors AND uses bold font
4. **Dim + Underline**: Reduces brightness AND draws underline

All combinations work correctly because:
- Font selection happens independently (based on bold/italic flags)
- Decorations are rendered procedurally (based on underline/strikethrough flags)
- Color modifications apply last (dim, inverse)

## Testing Commands

Test all attributes with these terminal commands:

```bash
# Basic attributes
echo -e "\033[1mBold Text\033[0m"
echo -e "\033[3mItalic Text\033[0m"
echo -e "\033[2mDim Text\033[0m"
echo -e "\033[7mInverse Video\033[0m"

# Underline types
echo -e "\033[4mSingle Underline\033[0m"
echo -e "\033[21mDouble Underline\033[0m"
echo -e "\033[4:3mCurly Underline\033[0m"
echo -e "\033[4:4mDotted Underline\033[0m"
echo -e "\033[4:5mDashed Underline\033[0m"

# Strikethrough
echo -e "\033[9mStrikethrough Text\033[0m"

# Combinations
echo -e "\033[1;3mBold Italic\033[0m"
echo -e "\033[1;4mBold Underlined\033[0m"
echo -e "\033[3;9mItalic Strikethrough\033[0m"
echo -e "\033[1;3;4;9mBold Italic Underlined Strikethrough\033[0m"
```

## Debugging Text Attributes

### 1. Verify Font Loading

Check logcat for font loading messages:
```
INFO font_system: Regular font face loaded (X bytes)
INFO font_system: Bold font face loaded (X bytes)
INFO font_system: Italic font face loaded (X bytes)
INFO font_system: Bold-Italic font face loaded (X bytes)
```

### 2. Enable Shader Debug Mode

In `cell_text.f.glsl`, uncomment lines 114-126 to visualize:
- Green pixels: Inside glyph bounds
- Red pixels: Outside glyph bounds (decoration area)

### 3. Check Attribute Propagation

Add logging in `renderer.zig` at line 632:
```zig
log.debug("Cell attributes: bold={}, italic={}, underline={}, strikethrough={}", .{
    cell.bold, cell.italic, cell.underline, cell.strikethrough
});
```

### 4. Verify Atlas Layout

The font atlas is organized in a 2x2 grid:
```
+----------+----------+
| Regular  | Bold     |
+----------+----------+
| Italic   | Bold+    |
|          | Italic   |
+----------+----------+
```

## Common Issues and Solutions

### Issue: Bold/Italic Not Showing

**Cause**: Font files not embedded correctly

**Solution**: Verify font files exist in `android/renderer/src/`:
- `JetBrainsMonoNerdFont-Bold.ttf`
- `JetBrainsMonoNerdFont-Italic.ttf`
- `JetBrainsMonoNerdFont-BoldItalic.ttf`

### Issue: Underline/Strikethrough Not Visible

**Cause**: Quad not expanding properly

**Solution**: Check vertex shader logs for expand_to_cell logic

### Issue: Inverse Video Not Working

**Cause**: Color swap not happening

**Solution**: Verify line 103-105 in fragment shader

### Issue: Attributes Lost

**Cause**: Bit packing/unpacking error

**Solution**: Log attribute values at each stage of pipeline

## Performance Characteristics

- **Font Atlas**: Single texture, 2x2 quadrants for 4 styles
- **Quad Expansion**: Only for cells with decorations (minimal overhead)
- **Procedural Decorations**: No texture lookups, pure math
- **Attribute Packing**: 16 bits per cell (very compact)

## Future Enhancements

1. **Colored Decorations**: Support colored underlines (SGR 58/59)
2. **More Underline Styles**: Wavy, thick, etc.
3. **Text Effects**: Shadow, outline, glow
4. **Per-Cell Background**: Move BG color to fragment shader (SSBO limitation workaround)
5. **Font Bearings**: Implement proper glyph positioning

## Conclusion

The Ghostty Android renderer has a **complete, production-ready implementation** of all terminal text attributes. The system uses:
- Real font faces for authentic bold/italic rendering
- Efficient procedural decoration generation
- Proper color handling for dim/inverse
- Optimized GPU data structures

If text attributes aren't rendering correctly, check:
1. Font file embedding
2. Terminal escape sequence processing
3. OpenGL driver/state issues

The renderer architecture itself is correct and complete.