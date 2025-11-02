# Android Build Setup for libghostty-vt

This document describes the build system setup for cross-compiling Ghostty's libghostty-vt library for Android targets.

## Overview

We successfully created a build system that uses:
- **Nix** for dependency management (including Zig 0.15.2)
- **Makefile** for build task automation
- **Zig** for cross-compilation to Android ABIs
- **Android NDK** for Android-specific toolchain and libraries

## Build Infrastructure

### 1. Nix Development Environment (`shell.nix`)

Provides:
- **Fully Nix-provisioned Android SDK/NDK** (no manual installation required!)
- Android NDK 27.0.12077973 with complete toolchain
- Android SDK with API levels 24 and 34
- Build tools 30.0.3 and 34.0.0
- Java 17, GNU Make, and Android platform tools (adb, fastboot)
- Automatic setup of `ANDROID_HOME` and `ANDROID_NDK_ROOT` environment variables
- AAPT2 override for NixOS compatibility

### 2. Build Scripts

#### `scripts/generate-android-libc.sh`
Generates Zig libc configuration for Android NDK with:
- Auto-detection of NDK Clang version (auto-detected from Nix-provided NDK)
- Architecture-specific paths for headers and libraries
- Critical `static_crt_dir` field pointing to Clang runtime libraries

**Key paths configured:**
- `include_dir`: NDK sysroot includes
- `sys_include_dir`: Architecture-specific system includes
- `crt_dir`: C runtime directory for specific API level
- `static_crt_dir`: Clang runtime libraries (e.g., `lib/clang/21/lib/linux/aarch64`)

#### `scripts/build-android-abi.sh`
Main build script that:
1. Validates environment (ABI, NDK paths)
2. Generates libc configuration
3. Runs `zig build` with proper cross-compilation flags
4. Copies built library to Android JNI directory

### 3. Makefile Targets

```makefile
make setup          # Clone Ghostty submodule
make build-native   # Build for all Android ABIs
make build-abi ABI=arm64-v8a  # Build for specific ABI
make clean          # Clean build artifacts
```

Supported ABIs:
- `arm64-v8a` (aarch64-linux-android)
- `armeabi-v7a` (armv7a-linux-androideabi)
- `x86_64` (x86_64-linux-android)

## Key Technical Solutions

### 1. Zig and Android NDK Integration

**Research findings:**
- Zig supports Android cross-compilation as a first-class feature
- The `--libc` flag is the correct way to specify Android NDK libc paths
- `ZIG_LIBC` environment variable doesn't work reliably with `zig build`

**Implementation:**
```bash
zig build lib-vt \
    -Dtarget=aarch64-linux-android.24 \
    -Doptimize=ReleaseFast \
    -Dapp-runtime=none \
    -Dsimd=false \
    -Dcpu=baseline \
    --libc ../build/android-arm64-v8a-libc.txt
```

### 2. Critical libc Configuration Fields

The `static_crt_dir` field was missing initially, causing linking errors. This field must point to:
```
$NDK/toolchains/llvm/prebuilt/linux-x86_64/lib/clang/$VERSION/lib/linux/$ARCH
```

### 3. SIMD Disabled

Android builds require `-Dsimd=false` to avoid C++ dependencies (simdutf, highway) that don't compile well with Android's Bionic libc.

### 4. Library Naming

The built library is named `libghostty-vt.so` (with hyphen), not `libghostty_vt.so` (with underscore).

## Build Output

**Successful build for ARM64:**
- **File**: `android/app/src/main/jniLibs/arm64-v8a/libghostty-vt.so`
- **Size**: 1.5 MB
- **Target**: aarch64-linux-android API 24
- **Optimizations**: ReleaseFast (SIMD disabled)

## Build Process

1. Enter nix-shell environment (downloads Android SDK/NDK automatically):
   ```bash
   nix-shell
   ```

   **Note**: First run will download ~350 MB of Android SDK/NDK components from Nix cache. This is a one-time download and will be cached.

2. Build for specific ABI:
   ```bash
   make build-abi ABI=arm64-v8a
   ```

3. Or build for all ABIs:
   ```bash
   make build-native
   ```

## No Manual Setup Required!

Unlike traditional Android development, you do **not** need to:
- ❌ Install Android Studio
- ❌ Download the Android SDK manually
- ❌ Install the NDK separately
- ❌ Configure `ANDROID_HOME` or `ANDROID_NDK_ROOT`
- ❌ Accept licenses manually

Everything is provided and configured automatically by Nix!

## Troubleshooting

### Issue: "unable to provide libc for target"
**Solution**: Ensure `--libc` flag points to properly configured Android NDK libc file with all required fields including `static_crt_dir`.

### Issue: C++ compilation errors (strings.h, wchar.h)
**Solution**: Add `-Dsimd=false` flag to disable C++ SIMD dependencies.

### Issue: Wrong Clang version path
**Solution**: The script now auto-detects the Clang version from NDK instead of hardcoding it.

### Issue: Library not found after build
**Solution**: Check for `libghostty-vt.so` (with hyphen), not `libghostty_vt.so` (with underscore).

## Research References

Key insights from web research on Zig + Android NDK:
1. Zig treats cross-compilation as first-class with built-in Android support
2. The `--libc` flag is required for custom libc configurations
3. Android's Bionic libc has limitations compared to glibc/musl
4. `static_crt_dir` is essential for linking with Clang runtime libraries

## Next Steps

- Build for armeabi-v7a and x86_64 ABIs
- Create JNI bindings for Android (Java/Kotlin)
- Develop Android terminal UI using libghostty-vt
- Set up CI/CD for automated builds
