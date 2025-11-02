# Ghostty Android Renderer - Implementation Status

## Overview

This document tracks the implementation of the Zig-based OpenGL ES 3.1 renderer for Ghostty Android.

**Architecture Decision**: Using Zig for renderer implementation to achieve 70-80% code reuse from the desktop OpenGL 4.3 renderer.

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

## What Works Now

1. ✅ **Build System**: Can compile Zig renderer for all Android ABIs (arm64-v8a, armeabi-v7a, x86_64)
2. ✅ **JNI Integration**: Native code loads and initializes successfully
3. ✅ **OpenGL ES Context**: GL context creation and management working
4. ✅ **Proof of Concept**: Renders solid color (purple) to screen
5. ✅ **Lifecycle**: Proper pause/resume/destroy handling
6. ✅ **Version Detection**: Checks for OpenGL ES 3.1 support at runtime

---

## Next Steps (Phase 2)

### Immediate: Complete Proof of Concept
**Goal**: Render a colored rectangle (not just clear screen)

**Tasks**:
1. Create simple vertex shader (GLSL 310 es)
2. Create simple fragment shader (GLSL 310 es)
3. Compile shaders in native code
4. Create vertex buffer with rectangle coordinates
5. Render rectangle in `nativeOnDrawFrame()`

**Estimated**: 1-2 days

### Shader Conversion (Required for all pipelines)
**Tasks**:
1. Create shader conversion script
2. Convert `common.glsl` to ES 3.1
3. Convert all 5 pipeline shaders (bg_color, cell_bg, cell_text, image, bg_image)

**Key Changes**:
- `#version 430 core` → `#version 310 es`
- Add `precision highp float;` and `precision highp int;`
- Replace `sampler2DRect` → `sampler2D` + normalize coordinates
- Test compilation on device

**Estimated**: 2-3 days

### Core Renderer Porting
**Tasks**:
1. Port `buffer.zig` for UBO/SSBO management
2. Port `Texture.zig` for font atlas
3. Port `Pipeline.zig` for render pipeline setup
4. Port `shaders.zig` for shader compilation
5. Adapt `OpenGL.zig` for ES 3.1 mode

**Estimated**: 1 week

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
2. Screen displays solid purple color (0.4, 0.2, 0.6, 1.0)
3. Logcat shows:
   ```
   I/GhosttyRenderer: Successfully loaded libghostty_renderer.so
   I/GhosttyRenderer: OpenGL Version: OpenGL ES 3.1 ...
   I/GhosttyRenderer: OpenGL Renderer: <GPU name>
   I/GhosttyRenderer: OpenGL ES Version: 3.1
   I/GhosttyRenderer: Renderer initialized successfully
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

## Known Limitations (Phase 1)

1. **No Actual Terminal Rendering**: Currently just clears screen with solid color
2. **No Shaders**: Shader pipeline not yet implemented
3. **No Text Rendering**: Font atlas and glyph rendering pending
4. **No Terminal Integration**: libghostty-vt VT parser not connected yet
5. **Fixed Terminal Size**: Hardcoded to 80x24

These are all expected for Phase 1 (Proof of Concept).

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
- **Next Milestone**: Render actual rectangle with shaders (1-2 days)
- **Phase 2 Target**: Core renderer working with text (2-3 weeks)

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

Last Updated: 2025-11-02
