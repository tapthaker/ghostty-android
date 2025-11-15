# Ghostty Android Renderer - Quick Reference Guide

## Document Index

### Main Documentation
- **RENDERER_ARCHITECTURE.md** - Comprehensive 1,148-line analysis (39 KB)
  - Complete architecture overview
  - All technical details and code flow
  - Testing considerations
  - Performance analysis

---

## Attribute Implementation Quick Lookup

| Attribute | Status | Implementation | Location |
|-----------|--------|-----------------|----------|
| **Bold** | ✅ Complete | Font face selection | `font_system.zig:494-502` |
| **Italic** | ✅ Complete | Font face selection | `font_system.zig:494-502` |
| **Underline** | ✅ Complete | Procedural rendering | `cell_text.f.glsl:54-86` |
| **Strikethrough** | ✅ Complete | Procedural rendering | `cell_text.f.glsl:89-94` |
| **Dim** | ✅ Complete | 50% brightness | `cell_text.f.glsl:234-236` |
| **Inverse** | ✅ Complete | Color swap | `cell_text.f.glsl:101-105` |

---

## Data Flow Map

```
libghostty-vt Terminal
├─ Cell: codepoint, fg_color, bg_color, style_flags
│         {bold, italic, underline, strikethrough, dim, inverse}
│
↓ screen_extractor.zig:51-143 (extractCells)
│
CellData struct
├─ codepoint: u21
├─ fg_color: [4]u8 (RGBA)
├─ bg_color: [4]u8 (RGBA)
├─ col: u16, row: u16
└─ Attributes: bold, italic, dim, underline, strikethrough, inverse
│
↓ renderer.zig:587-666 (syncFromTerminal)
│
├─ Background: cell_bg_colors[] → cells_bg_buffer (SSBO @ binding 1)
└─ Text: CellText[] → glyphs_buffer (VBO)
   ├─ glyph_pos: [x, y] in atlas
   ├─ grid_pos: [col, row]
   ├─ color: [r, g, b, a]
   └─ attributes: u16 (packed bits)
│
↓ GPU Rendering (3 passes)
│
├─ Pass 1: bg_color_pipeline (global background)
├─ Pass 2: cell_bg_pipeline (per-cell backgrounds from SSBO)
└─ Pass 3: cell_text_pipeline (text with attributes)
   ├─ Vertex shader: cell_text.v.glsl (192 lines)
   │  ├─ Grid→world conversion
   │  ├─ Quad generation from vertex ID
   │  ├─ Quad expansion for decorations
   │  └─ Glyph bounds calculation
   └─ Fragment shader: cell_text.f.glsl (251 lines)
      ├─ Glyph bounds checking
      ├─ Texture sampling
      ├─ Decoration rendering
      ├─ Attribute application
      └─ Color blending
```

---

## Key Code Locations

### Text Attribute Structures
- **CellData** (with attributes) - `screen_extractor.zig:16-48`
- **CellText.Attributes** (16-bit packed) - `shaders.zig:122-139`
- **Bit layout reference** - `cell_text.v.glsl:35-42` (shader masks)

### Attribute Extraction
- **Extract from VT** - `screen_extractor.zig:75-139`
  - Color palette lookup
  - Underline enum conversion
  - Style flags extraction
- **Convert to GPU format** - `renderer.zig:631-639`
  - Attributes struct creation
  - Enum conversion

### Font System
- **FontSystem struct** - `font_system.zig:34-215`
  - 4 font faces (regular, bold, italic, bold_italic)
  - 4 atlas structures
  - Font metrics calculation
- **Atlas layout** - `font_system.zig:313-362`
  - 2×2 quadrant layout
  - 16 glyphs per row
  - Position calculation
- **Glyph rendering** - `font_system.zig:364-482`
  - Bitmap centering
  - Baseline alignment
  - Atlas storage
- **CellText creation** - `font_system.zig:486-517`
  - Style selection from attributes
  - Atlas position lookup

### GPU Buffers
- **Buffer definitions** - `shaders.zig:13-158`
  - Uniforms struct (std140)
  - CellText instance data
  - AtlasDimensions
- **Buffer binding points** - `renderer.zig:98-165`
  - Binding 0: Global uniforms (UBO)
  - Binding 1: Per-cell backgrounds (SSBO)
  - Binding 2: Atlas dimensions (UBO)

### Shader Pipeline
- **Vertex shader** - `shaders/glsl/cell_text.v.glsl`
  - Grid→world conversion: Line 68
  - Quad expansion logic: Lines 120-159
  - Glyph bounds calculation: Lines 137-141
  - Attribute passing: Lines 190-191
- **Fragment shader** - `shaders/glsl/cell_text.f.glsl`
  - Underline detection: Lines 54-86
  - Strikethrough detection: Lines 89-94
  - Glyph bounds checking: Lines 107-109
  - Inverse video: Lines 101-105
  - Dim effect: Lines 234-236
  - Decoration application: Lines 241-248
- **Common code** - `shaders/glsl/common.glsl`
  - Global uniforms definition: Lines 19-31
  - Unpack functions: Lines 51-72
  - Color functions: Lines 78-159

### Rendering Pipeline
- **Main render loop** - `renderer.zig:433-493`
  - syncFromTerminal: Lines 587-666
  - Pass 1 (bg_color): Line 446
  - Pass 2 (cell_bg): Line 450
  - Pass 3 (cell_text): Lines 459-492

---

## Underline Type Reference

Fragment shader implementation: `cell_text.f.glsl:54-86`

```glsl
UNDERLINE_NONE   = 0   → No underline
UNDERLINE_SINGLE = 1   → Line at y = 0.88
UNDERLINE_DOUBLE = 2   → Two lines at y = 0.82 and 0.92
UNDERLINE_CURLY  = 3   → Sine wave: sin(x * 20.0) * 0.03
UNDERLINE_DOTTED = 4   → Pattern: mod(x, 0.15) < 0.06
UNDERLINE_DASHED = 5   → Pattern: mod(x, 0.25) < 0.15
```

All use thickness = 0.04 (4% of cell height)

---

## Attribute Bit Layout

CellText.Attributes (16-bit packed struct):
```
Bit 0:     bold
Bit 1:     italic
Bit 2:     dim
Bit 3:     strikethrough
Bits 4-6:  underline type (3-bit enum)
Bit 7:     inverse
Bits 8-15: padding (unused)
```

Shader masks (GLSL):
```glsl
ATTR_BOLD          = 1u
ATTR_ITALIC        = 2u
ATTR_DIM           = 4u
ATTR_STRIKETHROUGH = 8u
ATTR_UNDERLINE_MASK = 112u       // 0b0111_0000
ATTR_UNDERLINE_SHIFT = 4u
ATTR_INVERSE       = 128u
```

---

## Quad Expansion Logic

**When to expand**: If `has_underline || has_strikethrough || has_inverse`

**In vertex shader** (Lines 120-159 of cell_text.v.glsl):
```zig
if (expand_to_cell) {
    // Save original glyph bounds (normalized 0.0-1.0)
    out_glyph_bounds = vec4(glyph_start, glyph_end);
    
    // Expand to full cell
    size = cell_size;
    offset = vec2(0.0);
}
```

**In fragment shader** (Lines 107-109 of cell_text.f.glsl):
```glsl
bool in_glyph = out_cell_coord in out_glyph_bounds;

if (in_glyph) {
    sample_glyph_texture();
} else {
    render_decorations_or_background();
}
```

---

## Testing Attributes

**Basic test cases** (from RENDERER_ARCHITECTURE.md Section 12):

```bash
# Single attributes
echo -e "\e[1mBold\e[0m"
echo -e "\e[3mItalic\e[0m"
echo -e "\e[2mDim\e[0m"
echo -e "\e[4mUnderline\e[0m"
echo -e "\e[9mStrikethrough\e[0m"
echo -e "\e[7mInverse\e[0m"

# Underline types
echo -e "\e[4mSingle\e[0m"
echo -e "\e[21mDouble\e[0m"
echo -e "\e[4:3mCurly\e[0m"
echo -e "\e[4:4mDotted\e[0m"
echo -e "\e[4:5mDashed\e[0m"

# Combinations
echo -e "\e[1;4mBold+Underline\e[0m"
echo -e "\e[7;1mInverse+Bold\e[0m"
```

---

## Performance Notes

- **Font system**: ~800 KB (4 faces + 1 atlas)
- **Per-frame glyphs**: ~60 KB for 80×24 terminal
- **GPU draws**: 3 calls per frame (optimal)
- **Instancing**: Single GL_TRIANGLE_STRIP call for all glyphs
- **Decorations**: Procedural (no texture overhead)
- **Bearings**: Accounted for in viewport padding

---

## Extensibility Checklist

**Easy additions** (single file):
- [ ] New underline style → Modify `isUnderline()` in `cell_text.f.glsl`
- [ ] New text color effect → Add logic in fragment shader
- [ ] Decoration thickness → Change `line_thickness` constants

**Medium additions** (multiple files):
- [ ] Variable font sizes → Regenerate atlas, update metrics
- [ ] Font switching → Reinitialize FontSystem
- [ ] Color emoji → Populate `atlas_color` texture

**Complex additions** (architecture):
- [ ] Text shaping (ligatures) → Integrate HarfBuzz
- [ ] CJK text → Add clustering logic
- [ ] Fallback fonts → Add font discovery

---

## Common Modifications

### Change underline position
- Location: `cell_text.f.glsl:59` (single) or `64-65` (double)
- Current: `underline_pos = 0.88` (88% down from top)

### Change line thickness
- Location: `cell_text.f.glsl:58` and `91`
- Current: `line_thickness = 0.04` (4% of cell height)

### Change strikethrough position
- Location: `cell_text.f.glsl:92`
- Current: `strike_pos = 0.52` (52% down, slightly above center)

### Add new underline type
1. Add enum value to `CellText.Attributes.Underline` (shaders.zig:131)
2. Add shader constant (cell_text.v.glsl:43-48)
3. Add detection logic to `isUnderline()` (cell_text.f.glsl:54-86)

---

## Debugging Tips

1. **Trace attribute values**
   - Check `screen_extractor.extractCells()` output
   - Verify `syncFromTerminal()` conversion
   - Inspect packed u16 bits in debugger

2. **Verify GPU side**
   - Use shader debug output (visual bounds checking)
   - Check buffer bindings match pipeline
   - Verify texture coordinates with visualization

3. **Test individual attributes**
   - Use single VT sequences (e.g., `\e[4m` only)
   - Verify each renders correctly alone
   - Then test combinations

4. **Performance profiling**
   - Monitor draw call count (should be 3)
   - Check texture upload frequency (once on init)
   - Profile fragment shader (main bottleneck)

---

## References

- **Architecture**: See RENDERER_ARCHITECTURE.md (Sections 1-8)
- **Shaders**: See RENDERER_ARCHITECTURE.md (Sections 3-4)
- **Fonts**: See RENDERER_ARCHITECTURE.md (Section 5)
- **Implementation Plan**: See docs/text-attributes-implementation.md
- **Source files**: All in `android/renderer/src/`

---

**Last Updated**: 2024-11-10  
**Document Version**: 1.0  
**Status**: Complete and Production-Ready
