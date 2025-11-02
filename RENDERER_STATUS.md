# Ghostty Android Renderer - Implementation Status

## Overview

This document tracks the implementation of the Zig-based OpenGL ES 3.1 renderer for Ghostty Android.

**Architecture Decision**: Using Zig for renderer implementation to achieve 70-80% code reuse from the desktop OpenGL 4.3 renderer.

**Current Status**: Phase 2 in Progress - Multiple pipelines working, test glyphs rendering ✅

---

## Phase 1: Foundation & Proof of Concept ✅ COMPLETE

### Completed Tasks

#### 1. Android Renderer Module Structure ✅
**Location**: `android/renderer/`

```
android/renderer/
├── build.zig                    # Zig build system for renderer
├── src/
│   ├── main.zig                 # JNI entry points (5 functions implemented)
│   └── jni_bridge.zig           # JNI helper utilities
├── shaders/
│   └── processed/               # OpenGL ES 3.1 converted shaders (TBD)
└── include/
    └── ghostty_renderer.h       # C header documenting JNI interface
```

**Key Features**:
- Zig build system configured for Android cross-compilation
- Links against `GLESv3`, `EGL`, `android`, `log`
- JNI bridge with proper error handling and Android logging
- OpenGL ES version detection (requires 3.1+)

#### 2. JNI Bridge Implementation ✅
**File**: `android/renderer/src/main.zig`

**Implemented Functions**:
1. `JNI_OnLoad()` - Library initialization
2. `JNI_OnUnload()` - Library cleanup
3. `nativeOnSurfaceCreated()` - OpenGL context initialization
4. `nativeOnSurfaceChanged(width, height)` - Viewport updates
5. `nativeOnDrawFrame()` - Frame rendering (currently clears screen with purple)
6. `nativeDestroy()` - Renderer cleanup
7. `nativeSetTerminalSize(cols, rows)` - Terminal size configuration (stub)

**Current Behavior**: Renders a solid purple screen (proof of concept)

#### 3. Kotlin GL Surface View ✅
**Files**:
- `android/app/src/main/java/com/ghostty/android/renderer/GhosttyRenderer.kt`
- `android/app/src/main/java/com/ghostty/android/renderer/GhosttyGLSurfaceView.kt`

**Features**:
- GLSurfaceView.Renderer implementation
- OpenGL ES 3.x context management
- Render mode: `RENDERMODE_WHEN_DIRTY` (power efficient)
- Touch event handling (placeholder)
- Lifecycle management (pause/resume)

#### 4. MainActivity Integration ✅
**File**: `android/app/src/main/java/com/ghostty/android/MainActivity.kt`

**Changes**:
- Replaced `TerminalView` with `GhosttyGLSurfaceView` via `AndroidView`
- Added lifecycle callbacks (`onPause()`, `onResume()`)
- GL surface view reference management
- Proper cleanup on destroy

#### 5. Build System Integration ✅

**CMakeLists.txt** (`android/app/src/main/cpp/CMakeLists.txt`):
```cmake
target_link_libraries(ghostty_bridge
    .../libghostty-vt.so
    .../libghostty_renderer.so  # NEW
    android
    log
    GLESv3  # NEW
    EGL     # NEW
)
```

**build-android-abi.sh** (`scripts/build-android-abi.sh`):
- Builds libghostty-vt for ABI
- **NEW**: Builds libghostty_renderer for ABI
- Copies both `.so` files to `jniLibs/${ABI}/`

**Makefile**:
- Updated `build-native` to build both libraries
- Updated help text to reflect renderer build

**AndroidManifest.xml**:
```xml
<uses-feature
    android:glEsVersion="0x00030001"  # OpenGL ES 3.1 required
    android:required="true" />
```

---

## Phase 2: Core Renderer Implementation ⚡ IN PROGRESS

### Completed Tasks

#### 1. Shader System Implementation ✅
**Files**: `android/renderer/src/shader.zig`
- GLSL ES 310 shader compilation with error reporting
- Include preprocessing for shader composition
- Automatic precision qualifier injection
- Build-time shader embedding

#### 2. Core Rendering Components ✅
**Files**: Multiple modules in `android/renderer/src/`
- **buffer.zig**: Generic typed buffers (VBO, UBO, SSBO)
- **texture.zig**: R8 and RGBA8 texture management for font atlases
- **pipeline.zig**: Render pipeline abstraction with VAO management
- **gl_es.zig**: OpenGL ES 3.1 wrapper with error checking

#### 3. Multiple Rendering Pipelines ✅

**Pipeline 1: Background Color** ✅
- Full-screen triangle rendering (no vertex buffer)
- Solid purple background confirmed working

**Pipeline 2: Cell Backgrounds** ✅
- SSBO-based per-cell background colors
- Red/green checkerboard pattern rendering successfully
- 80×24 grid (1920 cells) with packed RGBA8 colors

**Pipeline 3: Cell Text** ✅
- Instanced glyph rendering with dual font atlases
- R8 grayscale atlas (512×512) for regular text
- RGBA8 color atlas (512×512) for color emoji
- Test patterns rendering successfully (white square, gradient, checkerboard, cross)
- Fixed critical VAO/buffer binding order issue

#### 4. OpenGL ES 3.1 Compatibility Fixes ✅
- Removed SSBO `readonly` qualifier (not in ES 3.1)
- Programmatic sampler uniform binding
- Individual `in`/`out` variables instead of interface blocks (Mali-G57 compatibility)
- Proper switch statement syntax for Mali drivers
- Pixel alignment for R8 textures

### Current Achievements
- Three rendering pipelines working correctly
- Test glyphs rendering with distinct patterns
- Proper blending between pipelines
- Mali-G57 GPU compatibility confirmed
- Shader compilation and linking successful

### Remaining Work for Phase 2
- [ ] FreeType integration for actual glyph rasterization
- [ ] Connection to libghostty-vt parser
- [ ] Real terminal cell data rendering
- [ ] Pipeline 4: Terminal images
- [ ] Pipeline 5: Background image

---

## What Works Now

1. ✅ **Build System**: Can compile Zig renderer for all Android ABIs (arm64-v8a, armeabi-v7a, x86_64)
2. ✅ **JNI Integration**: Native code loads and initializes successfully
3. ✅ **OpenGL ES Context**: GL context creation and management working
4. ✅ **Multiple Render Pipelines**: Background, cell backgrounds, and text rendering working
5. ✅ **Shader System**: GLSL ES 3.1 shaders compiling and linking successfully
6. ✅ **Test Glyphs**: Rendering with distinct patterns (white square, gradient, checkerboard, cross)
7. ✅ **Buffer Management**: VBO, UBO, SSBO all working correctly
8. ✅ **Texture System**: Dual font atlases (R8 grayscale, RGBA8 color) initialized
9. ✅ **Lifecycle**: Proper pause/resume/destroy handling
10. ✅ **Version Detection**: Checks for OpenGL ES 3.1 support at runtime

---

## Next Steps (Phase 2 Completion)

### Immediate: FreeType Integration
**Goal**: Render actual terminal text (not just test patterns)

**Tasks**:
1. Integrate FreeType library for glyph rasterization
2. Populate font atlases with actual glyph bitmaps
3. Connect to terminal cell data from libghostty-vt
4. Test with real terminal text content

**Estimated**: 3-4 days

### Terminal Integration
**Tasks**:
1. Bridge TerminalSession to renderer
2. Expose grid data (text, colors, attributes)
3. Real-time cell updates
4. Cursor position synchronization
5. Selection highlighting
6. Scrollback rendering

**Estimated**: 1 week

### Remaining Pipelines
**Tasks**:
1. **Pipeline 4**: Terminal images (Kitty protocol support)
2. **Pipeline 5**: Background image rendering
3. Image texture management
4. Compositing and blending

**Estimated**: 3-4 days

---

## How to Test Current Implementation

### Build and Run

```bash
# Build everything (libghostty-vt + renderer + APK)
make android

# Or step by step:
make check-env
make setup
make build-native  # Builds both .so files
cd android && ./gradlew assembleDebug
cd android && ./gradlew installDebug
```

### Expected Behavior

1. App launches normally
2. Screen displays:
   - Purple background (Pipeline 1)
   - Red/green checkerboard pattern overlay (Pipeline 2)
   - Four test glyphs with distinct patterns in corners (Pipeline 3):
     - Top-left: White square
     - Top-right: Gradient pattern
     - Bottom-left: Checkerboard
     - Bottom-right: Cross pattern
3. Logcat shows:
   ```
   I/GhosttyRenderer: Successfully loaded libghostty_renderer.so
   I/GhosttyRenderer: OpenGL Version: OpenGL ES 3.2 ...
   I/GhosttyRenderer: OpenGL Renderer: Mali-G57 (or your GPU)
   I/GhosttyRenderer: Renderer initialized successfully
   I/GhosttyRenderer: Pipeline 1: Background color initialized
   I/GhosttyRenderer: Pipeline 2: Cell backgrounds initialized
   I/GhosttyRenderer: Pipeline 3: Cell text initialized
   I/GhosttyRenderer: Font atlases created (512x512 R8, 512x512 RGBA8)
   I/GhosttyRenderer: Rendering 4 test glyphs
   ```

### View Logs

```bash
# View all renderer logs
adb logcat | grep GhosttyRenderer

# Or use make target
make logs
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────┐
│   MainActivity (Kotlin)                 │
│   - Lifecycle management                │
│   - GL surface view reference           │
└─────────────┬───────────────────────────┘
              │
┌─────────────▼───────────────────────────┐
│   GhosttyGLSurfaceView (Kotlin)         │
│   - OpenGL ES 3.x context               │
│   - EGL configuration                   │
│   - Render thread management            │
└─────────────┬───────────────────────────┘
              │
┌─────────────▼───────────────────────────┐
│   GhosttyRenderer (Kotlin)              │
│   - onSurfaceCreated()                  │
│   - onSurfaceChanged()                  │
│   - onDrawFrame()                       │
└─────────────┬───────────────────────────┘
              │ JNI
┌─────────────▼───────────────────────────┐
│   libghostty_renderer.so (Zig)          │
│   - OpenGL ES 3.1 rendering             │
│   - Shader compilation                  │
│   - Buffer management                   │
│   - Texture atlas (future)              │
└─────────────┬───────────────────────────┘
              │
┌─────────────▼───────────────────────────┐
│   libGLESv3.so (Android System)         │
│   - OpenGL ES API                       │
└─────────────────────────────────────────┘
```

---

## Files Created (Phase 1)

### Native (Zig)
1. `android/renderer/build.zig` - Build system
2. `android/renderer/src/main.zig` - JNI bridge (372 lines)
3. `android/renderer/src/jni_bridge.zig` - JNI utilities (194 lines)
4. `android/renderer/include/ghostty_renderer.h` - C header

### Kotlin
1. `android/app/src/main/java/com/ghostty/android/renderer/GhosttyRenderer.kt` (137 lines)
2. `android/app/src/main/java/com/ghostty/android/renderer/GhosttyGLSurfaceView.kt` (149 lines)

### Build System
1. Updated `android/app/src/main/cpp/CMakeLists.txt`
2. Updated `scripts/build-android-abi.sh`
3. Updated `Makefile`
4. Updated `android/app/src/main/AndroidManifest.xml`
5. Updated `android/app/src/main/java/com/ghostty/android/MainActivity.kt`

**Total**: 9 new files, 5 modified files

---

## Dependencies

### Runtime
- Android API 24+ (Android 7.0+)
- OpenGL ES 3.1+ capable GPU
- EGL for context management

### Build Time
- Zig 0.15.2 (provided by ghostty nix-shell)
- Android NDK (via ANDROID_NDK_ROOT)
- Gradle (via Android build system)

---

## Known Limitations (Current)

1. **No Actual Font Data**: Using test patterns instead of real glyphs (FreeType integration pending)
2. **No Terminal Integration**: libghostty-vt VT parser not connected yet
3. **Fixed Terminal Size**: Hardcoded to 80x24
4. **First Frame Error**: GL_INVALID_OPERATION on first render (non-fatal)
5. **Missing Pipelines**: Terminal images and background image not yet implemented

---

## Success Criteria for Phase 1 ✅

- [x] Zig renderer module builds for all Android ABIs
- [x] Native library loads successfully in Android app
- [x] OpenGL ES 3.1 context created successfully
- [x] JNI bridge functional (function calls work)
- [x] Lifecycle handling implemented (pause/resume/destroy)
- [x] Colored screen renders (proof that GL commands work)
- [x] Build system integration complete
- [x] AndroidManifest declares OpenGL ES 3.1 requirement

**Status**: Phase 1 COMPLETE ✅

---

## Timeline

- **Phase 1 Start**: 2025-11-02
- **Phase 1 Complete**: 2025-11-02 (same day!)
- **Phase 2 Start**: 2025-11-02
- **Phase 2 Progress**: 2025-11-02 - Three pipelines working, test glyphs rendering
- **Next Milestone**: FreeType integration for actual font rendering (3-4 days)
- **Phase 2 Target**: Full terminal rendering with real text (1-2 weeks)

---

## Resources

### Code References
- Desktop renderer: `libghostty-vt/src/renderer/OpenGL.zig`
- Desktop shaders: `libghostty-vt/src/renderer/shaders/glsl/`
- Shader data structures: `libghostty-vt/src/renderer/opengl/shaders.zig`

### Documentation
- OpenGL ES 3.1 spec: https://www.khronos.org/registry/OpenGL/specs/es/3.1/
- Android NDK JNI guide: https://developer.android.com/ndk/guides/jni
- Zig Android cross-compilation: Ghostty's existing build system

---

Last Updated: 2025-11-02 (Phase 2 Progress - Glyph Rendering Working)
