# Ghostty Android - Build Guide

Complete guide for building Ghostty Android from source using the Nix-based build system.

## Quick Start

```bash
nix-shell              # Enter Nix environment (one-time ~350 MB download)
make android           # Build + install + launch
```

## Build System Overview

The project uses a **Makefile-based build system** with **Nix for dependency management**:

- **Nix** - Provisions Android SDK/NDK, Zig 0.15.2, JDK17, build tools
- **Makefile** - Orchestrates build tasks with automatic nix-shell detection
- **Zig** - Cross-compiles libghostty-vt to Android ABIs
- **Gradle** - Builds the Android APK
- **Android NDK** - Provides Android-specific toolchain

## Prerequisites

### Required: Nix Package Manager

Install Nix (if not already installed):
```bash
# Multi-user installation (recommended)
sh <(curl -L https://nixos.org/nix/install) --daemon

# Or single-user
sh <(curl -L https://nixos.org/nix/install) --no-daemon
```

### That's It!

No manual installation needed for:
- ❌ Android Studio
- ❌ Android SDK
- ❌ Android NDK
- ❌ Zig compiler
- ❌ Java JDK

Everything is provisioned automatically by Nix!

## Build Process

### 1. Enter Nix Shell

```bash
nix-shell
```

**First-time setup:** Downloads ~350 MB of Android SDK/NDK from Nix cache (one-time operation)

**What it provides:**
- Android SDK with API levels 24 and 34
- Android NDK 27.0.12077973 with complete toolchain
- Build tools 30.0.3 and 34.0.0
- Java 17, GNU Make, Git, Curl
- Android platform tools (adb, fastboot)
- Automatic `ANDROID_HOME` and `ANDROID_NDK_ROOT` configuration
- AAPT2 override for NixOS compatibility

### 2. Build Commands

**One-stop build** (recommended):
```bash
make android          # Builds native libs + APK, installs, and launches
```

**Step-by-step build:**
```bash
make build-native     # Build libghostty-vt + renderer for all ABIs
make build-android    # Build Android APK
make install          # Install APK to connected device
```

**Check configuration:**
```bash
make help             # Show all available targets
make check-env        # Verify environment variables
```

### 3. Build Output

**Native libraries:**
```
android/app/src/main/jniLibs/
├── arm64-v8a/
│   ├── libghostty-vt.so (~1.5 MB)
│   └── libghostty_renderer.so
├── armeabi-v7a/
│   ├── libghostty-vt.so
│   └── libghostty_renderer.so
└── x86_64/
    ├── libghostty-vt.so
    └── libghostty_renderer.so
```

**APK:**
```
android/app/build/outputs/apk/debug/app-debug.apk
```

## Supported Android ABIs

| ABI | Zig Target | Use Case |
|-----|------------|----------|
| arm64-v8a | aarch64-linux-android.24 | Modern ARM 64-bit devices |
| armeabi-v7a | armv7a-linux-androideabi.24 | Older ARM 32-bit devices |
| x86_64 | x86_64-linux-android.24 | Emulators |

Build for specific ABI:
```bash
make build-native ANDROID_ABIS="arm64-v8a"
```

## Build System Architecture

### Nix Environment (`shell.nix`)

Provisions complete Android development environment:
- Fully Nix-managed Android SDK/NDK (no manual installation)
- Version-locked dependencies for reproducibility
- Works identically on NixOS, Linux, and macOS

### Build Scripts

**`scripts/build-android-abi.sh`**
- Generates Zig libc configuration for Android NDK
- Auto-detects NDK Clang version
- Configures architecture-specific paths
- Enters Ghostty's nix-shell to run Zig builds
- Builds both libghostty-vt and OpenGL renderer
- Patches renderer with `patchelf` to add GL dependencies

**`scripts/generate-android-libc.sh`**
- Generates Zig libc configuration file
- Configures critical paths: include_dir, sys_include_dir, crt_dir, static_crt_dir
- Essential for Zig cross-compilation to Android

**`android/scripts/build-android.sh`**
- Builds Android APK using Gradle
- Optional `--install` flag to install after build

### Makefile Targets

See `make help` for full list. Key targets:
- `make android` - Full build + install + launch
- `make build-native` - Build native libraries
- `make build-android` - Build Android APK
- `make clean` - Clean build artifacts

All build targets automatically check for nix-shell and error with helpful message if not detected.

## Zig Cross-Compilation Details

### Configuration

```bash
zig build lib-vt \
    -Dtarget=aarch64-linux-android.24 \
    -Doptimize=ReleaseFast \
    -Dapp-runtime=none \
    -Dsimd=false \
    -Dcpu=baseline \
    --libc build/android-arm64-v8a-libc.txt
```

### Key Settings

- `--libc`: Points to Android NDK libc configuration (required)
- `-Dsimd=false`: Disables C++ SIMD dependencies incompatible with Android Bionic libc
- `-Dapp-runtime=none`: Builds library without app runtime
- `-Dcpu=baseline`: Ensures broad device compatibility

### Critical libc Fields

The generated libc configuration must include:
- `include_dir`: NDK sysroot includes
- `sys_include_dir`: Architecture-specific system includes
- `crt_dir`: C runtime directory for API level
- `static_crt_dir`: Clang runtime libraries (path like `lib/clang/21/lib/linux/aarch64`)

Missing `static_crt_dir` causes linking errors.

## NixOS-Specific Notes

### AAPT2 Issue ✅ SOLVED

The Nix environment automatically solves the AAPT2 dynamic linking issue on NixOS by:
1. Provisioning Android SDK via `androidenv.composeAndroidPackages`
2. Setting `GRADLE_OPTS` to override AAPT2 with Nix-provided binary
3. No FHS compatibility workarounds needed

### Benefits

- ✅ Works perfectly on NixOS (no FHS issues)
- ✅ Fully reproducible builds
- ✅ Version-locked dependencies
- ✅ Works identically across NixOS, Linux, macOS

## Troubleshooting

### "Not running inside nix-shell" error
**Solution:** Run `nix-shell` first, then your make command

### "ANDROID_HOME not set" error
**Solution:** Ensure you're in nix-shell (check prompt shows `[nix-shell]`)

### "unable to provide libc for target"
**Solution:** Ensure `scripts/generate-android-libc.sh` is working correctly. The script should auto-detect NDK paths from nix-shell.

### C++ compilation errors (strings.h, wchar.h)
**Already fixed:** Build uses `-Dsimd=false` to avoid C++ SIMD dependencies

### Library not found after build
**Check:** Look for `libghostty-vt.so` (with hyphen), not `libghostty_vt.so` (with underscore)

### Gradle build fails with AAPT2 errors (NixOS)
**Already fixed:** `shell.nix` sets `GRADLE_OPTS` to override AAPT2

### Build logs location
Build logs are saved to:
- `build/build-<ABI>.log` - Native library builds
- `build/build-renderer-<ABI>.log` - Renderer builds

## Development Workflow

**Full rebuild:**
```bash
nix-shell
make clean
make android
```

**Incremental rebuild:**
```bash
nix-shell
make build-native    # If Zig/C code changed
make build-android   # If Kotlin/Java code changed
make install
```

**Development with Android Studio:**
```bash
nix-shell
make android-studio  # Opens Android Studio with proper environment
```

**View logs:**
```bash
make logs  # Shows app logs from device
```

## Next Steps

After successful build:
1. Run tests: `make test-feedback-id TEST_ID=basic_colors_fg`
2. View status: See [DEV_STATUS.md](DEV_STATUS.md)
3. Understand architecture: See [ARCHITECTURE.md](ARCHITECTURE.md)
4. Renderer details: See [RENDERER_ARCHITECTURE.md](RENDERER_ARCHITECTURE.md)
