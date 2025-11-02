# Ghostty Android Renderer Progress

**Last Updated:** 2025-11-02
**Status:** Pipeline 1-3 Complete ✅ | Test Glyphs Rendering ✅

---

## Overview

This document tracks the implementation progress of the Ghostty Android renderer, which ports the desktop OpenGL renderer to OpenGL ES 3.1/3.2 for Android devices.

## Architecture

The renderer uses a multi-pass rendering pipeline architecture:
1. **Pipeline 1:** Background color (solid color fill)
2. **Pipeline 2:** Cell backgrounds (SSBO-based per-cell colors)
3. **Pipeline 3:** Cell text (instanced glyph rendering with font atlases)
4. **Pipeline 4:** Terminal images (Kitty protocol support)
5. **Pipeline 5:** Background image

---

## Completed Work ✅

### Core Renderer Infrastructure

- **OpenGL ES 3.1 Wrapper** (`gl_es.zig`)
  - Shader compilation with error reporting
  - Program linking and uniform management
  - Buffer objects (VBO, UBO, SSBO)
  - Texture management
  - Vertex array objects (VAO)
  - Error checking utilities

- **Shader System** (`shader.zig`)
  - `#include` preprocessing for shader composition
  - GLSL ES 310 version enforcement
  - Precision qualifier injection
  - Build-time shader embedding with `@embedFile`

- **Buffer Management** (`buffer.zig`)
  - Generic typed buffers (VBO, UBO, SSBO)
  - Automatic size calculation
  - Sync operations for data upload
  - Indexed binding for UBO/SSBO

- **Texture System** (`texture.zig`)
  - R8 and RGBA8 format support
  - Texture unit binding
  - Region updates
  - Proper lifetime management

- **Pipeline Abstraction** (`pipeline.zig`)
  - Automatic vertex attribute configuration
  - VAO management
  - Blending control
  - Per-vertex/per-instance step functions

### Pipeline 1: Background Color ✅

**Status:** Complete and tested  
**Commit:** `a265a69`

- Full-screen triangle rendering (no vertex buffer)
- Uses global background color from Uniforms UBO
- Single-pass rendering with `bg_color.f.glsl`
- Verified working on Mali-G57 GPU

### Pipeline 2: Cell Backgrounds ✅

**Status:** Complete and tested  
**Commit:** `8f2d147`

**Implementation:**
- SSBO at binding point 1 for per-cell background colors
- 80×24 grid (1920 cells) with packed RGBA8 colors
- Full-screen triangle with fragment shader cell lookup
- Blending enabled for compositing over Pipeline 1

**Shaders:**
- `cell_bg.f.glsl` - Grid-based SSBO lookup with padding extension

**Test Pattern:**
- Checkerboard: alternating red (128,0,0,255) and green (0,128,0,255)
- Successfully renders on device

**Challenges Solved:**
- Removed `readonly` qualifier (not in ES 3.1 spec)
- Changed UBO binding from 1→0 to avoid SSBO conflict

### Pipeline 3: Cell Text Rendering ✅

**Status:** Complete - Test glyphs rendering successfully
**Commits:** `e42a364`, `19ca269`, `9d7548a`

**Completed:**
- R8 grayscale font atlas (512×512) for regular text
- RGBA8 color atlas (512×512) for color emoji
- AtlasDimensions UBO (binding point 2) for coordinate normalization
- Glyph instance buffer (`Buffer<CellText>`)
- Automatic vertex attribute setup for instanced rendering
- Programmatic sampler uniform binding (ES 3.1 requirement)

**Shaders:**
- `cell_text.v.glsl` - Instanced glyph quad generation
- `cell_text.f.glsl` - Dual-atlas sampling with linear blending

**Data Structures:**
```zig
pub const CellText = extern struct {
    glyph_pos: [2]u32,      // Atlas position
    glyph_size: [2]u32,     // Glyph dimensions
    bearings: [2]i16,       // Font metrics
    grid_pos: [2]u16,       // Terminal grid position
    color: [4]u8,           // Text color (RGBA8)
    atlas: Atlas,           // Grayscale or color
    bools: packed struct {  // Flags
        no_min_contrast: bool,
        is_cursor_glyph: bool,
    },
};
```

**Fixed Issues:** ✅
1. **Interface block incompatibility** - Mali-G57 requires individual `in`/`out` variables instead of interface blocks
2. **Switch statement syntax** - `default` case must come last, use `break` instead of `return`
3. **SSBO in vertex shader** - Mali-G57 doesn't support SSBOs in vertex shaders (max=0), using global bg color instead
4. **Logging configuration** - Added custom `std_options.logFn` to output Zig logs to Android logcat
5. **VAO/Buffer binding order** - Fixed critical issue where VAO was configured without buffer bound, preventing vertex attributes from accessing instance data

**Test Pattern Results:** ✅
- White square (solid 255 fill) in top-left
- Gradient pattern (0-255 ramp) in top-right
- Checkerboard pattern in bottom-left
- Cross pattern in bottom-right
- All 4 test glyphs render correctly with distinct patterns

---

## OpenGL ES 3.1 Compatibility Fixes

### Issues Encountered & Resolved

1. **SSBO `readonly` qualifier** 
   - ❌ Desktop OpenGL 4.3+ feature
   - ✅ Removed from all SSBO declarations

2. **Sampler `layout(binding = N)`**
   - ❌ Not supported in ES 3.1
   - ✅ Use `glUniform1i()` programmatically

3. **UBO/SSBO binding conflicts**
   - ❌ Both using binding point 1
   - ✅ UBO→0, SSBO→1, AtlasDimensions UBO→2

4. **Type casting for `glActiveTexture()`**
   - ❌ `c.GL_TEXTURE0 + unit` type mismatch
   - ✅ Cast to `c.GLenum` explicitly

5. **Coordinate system differences**
   - ❌ `layout(origin_upper_left)` not in ES
   - ✅ Manual Y-flip in fragment shaders

6. **Precision qualifiers**
   - ❌ Required in ES, not in desktop GL
   - ✅ Auto-inject `precision highp float;` via shader module

7. **Interface blocks in shaders**
   - ❌ Mali drivers have compatibility issues with interface blocks
   - ✅ Use individual `in`/`out` variables instead

8. **SSBO in vertex shaders**
   - ❌ Mali-G57 doesn't support SSBOs in vertex shaders (`MAX_VERTEX_SHADER_STORAGE_BLOCKS = 0`)
   - ✅ Move SSBO access to fragment shader or use alternative approach

9. **Switch statement syntax**
   - ❌ `default:` before `case` labels causes issues on some drivers
   - ✅ Place `default:` at the end, use `break` instead of `return`

10. **Zig logging on Android**
    - ❌ `std.log.scoped()` doesn't output to logcat by default
    - ✅ Configure `std_options.logFn` to use `__android_log_print`

---

## Testing & Verification

### Test Environment
- **Device:** Physical Android device
- **GPU:** Mali-G57
- **OpenGL ES:** 3.2
- **Build Targets:** arm64-v8a, armeabi-v7a, x86_64

### Visual Verification
- ✅ Purple background rendering (Pipeline 1)
- ✅ Red/green checkerboard pattern (Pipeline 2)
- ✅ Cell text shaders compile and link successfully (Pipeline 3)
- ✅ Test glyphs render with distinct patterns (white square, gradient, checkerboard, cross)

### Build System
- ✅ Zig cross-compilation to Android
- ✅ NDK integration (API level 24+)
- ✅ Multi-ABI builds in parallel
- ✅ Automatic dependency injection (libGLESv3.so, liblog.so)

---

## Pending Work 🔲

### Pipeline 3: Cell Text (Complete ✅)
- [x] Debug cell_text shader compilation failures
- [x] Fix interface block incompatibility (Mali-G57)
- [x] Fix SSBO vertex shader limitation (Mali-G57)
- [x] Fix switch statement syntax issues
- [x] Shaders compile and link successfully
- [x] Fix VAO/buffer binding order issue
- [x] Verify glyph rendering with test patterns
- [x] Test atlas sampling and coordinate normalization
- [ ] Populate font atlases with actual glyph data (FreeType integration)
- [ ] Verify linear blending and correction with real glyphs
- [ ] Test cursor color override
- [ ] Test minimum contrast enforcement

### Pipeline 4: Terminal Images
- [ ] Image texture management
- [ ] Kitty protocol image placement
- [ ] Source rect and dest size handling
- [ ] Image compositing

### Pipeline 5: Background Image
- [ ] Background image loading
- [ ] Fit modes (contain, cover, stretch, none)
- [ ] Position modes (9 positions)
- [ ] Repeat/tile support
- [ ] Opacity control

### Terminal Integration
- [ ] Bridge TerminalSession to renderer
- [ ] Expose grid data (text, colors, attributes)
- [ ] Font atlas population from FreeType
- [ ] Real-time cell updates
- [ ] Cursor position synchronization
- [ ] Selection highlighting
- [ ] Scrollback rendering

### Performance Optimization
- [ ] Profile frame times
- [ ] Optimize SSBO updates (dirty regions)
- [ ] Batch glyph instances
- [ ] Texture atlas packing
- [ ] Target 60 FPS on mid-range devices

---

## Technical Decisions

### Why SSBO for Cell Backgrounds?
- Direct GPU access to per-cell data
- No CPU→GPU copy per frame for static cells
- Efficient for 80×24×many frames

### Why Instanced Rendering for Text?
- Single draw call for all visible glyphs
- GPU-friendly batching
- Per-glyph attributes via instance buffer

### Why Dual Font Atlases?
- R8 grayscale: space-efficient for monochrome text
- RGBA8 color: required for emoji/color glyphs
- Separate atlases allow format specialization

### Why Full-Screen Triangle?
- No vertex buffer needed (procedural generation)
- Two pipelines use this: bg_color, cell_bg
- Simpler than full-screen quad

---

## Build & Install

```bash
# Build for all ABIs
make android

# Install APK
adb install android/app/build/outputs/apk/debug/app-debug.apk

# View logs
adb logcat | grep -E "(GhosttyRenderer|Shader)"
```

---

## Code Statistics

**Files:** 12 core renderer modules  
**Lines:** ~2,500 (Zig + GLSL)  
**Shaders:** 10 GLSL files (vertex + fragment)  
**Commits:** 3 major milestones

---

## Known Issues

1. **First frame rendering error**
   - `error.InvalidOperation` on first `onDrawFrame` call
   - Subsequent frames succeed without error
   - Does not prevent rendering from working
   - Likely related to uniform initialization timing

2. **No real font glyph data yet**
   - Currently using test patterns (white square, gradient, checkerboard, cross)
   - Need FreeType integration for actual glyph rasterization
   - Test patterns confirm rendering pipeline is working correctly

3. **Per-cell background colors disabled in vertex shader**
   - Mali-G57 doesn't support SSBOs in vertex shaders
   - Currently using global background color only in vertex shader
   - Fragment shader still has access to SSBO for per-cell colors

---

## References

- [GLSL ES 3.1 Specification](https://www.khronos.org/registry/OpenGL/specs/es/3.1/GLSL_ES_Specification_3.10.pdf)
- [OpenGL ES 3.1 API](https://www.khronos.org/registry/OpenGL-Refpages/es3.1/)
- [Ghostty Desktop Renderer](https://github.com/ghostty-org/ghostty/tree/main/src/renderer)
