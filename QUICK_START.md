# Ghostty Android - Quick Start Guide

## Recommended: Build with Android Studio (NixOS)

The easiest way to build on NixOS:

```bash
make android-studio
```

This will:
1. ✅ Build libghostty-vt for all Android ABIs (arm64-v8a, armeabi-v7a, x86_64)
2. ✅ Open Android Studio in FHS environment
3. ✅ Let you build APK with one click (Build → Build APK)

## Alternative: Command-Line Build (Standard Linux)

If you're on a standard Linux distribution (not NixOS):

```bash
make android
```

This single command will:
1. ✅ Build libghostty-vt for all Android ABIs
2. ✅ Build the Android APK with Gradle
3. ✅ Install on your connected device

**Note**: On NixOS, this may fail due to AAPT2 compatibility. Use `make android-studio` instead or see `docs/NIXOS_BUILD.md` for solutions.

## Prerequisites

### 1. Development Environment

```bash
# Install Nix (if not already installed)
sh <(curl -L https://nixos.org/nix/install)

# Enter the development shell
nix-shell
```

This provides:
- Zig compiler (0.15.2 from Ghostty's environment)
- Android SDK/NDK auto-detection
- All build tools

### 2. Android Device Setup

```bash
# Enable USB debugging on your Android device
# Settings → About Phone → Tap "Build Number" 7 times
# Settings → Developer Options → Enable "USB Debugging"

# Connect device and verify
adb devices
```

You should see:
```
List of devices attached
XXXXXXXX    device
```

## Build Commands

### Full Build (Recommended)

```bash
make android
```

Builds everything and installs to device.

### Individual Steps

```bash
# 1. Build native libraries only
make build-native

# 2. Build Android APK only (requires native libraries)
make build-android

# 3. Install APK only (requires APK)
make install
```

### Quick Build for Single ABI

```bash
# Build for ARM64 only (faster for testing)
make build-abi ABI=arm64-v8a
cd android && ./gradlew installDebug
```

## Viewing Logs

```bash
# Real-time logs from the app
adb logcat | grep -E "(GhosttyBridge|TerminalSession|MainActivity)"

# Clear logcat first for cleaner output
adb logcat -c && adb logcat | grep -E "(GhosttyBridge|TerminalSession)"
```

## Project Structure

```
ghostty-android/
├── Makefile                    # Build automation (USE THIS!)
├── libghostty-vt/              # Ghostty submodule (VT parser)
├── android/                    # Android application
│   ├── app/
│   │   ├── src/main/
│   │   │   ├── cpp/           # JNI bridge (C)
│   │   │   ├── java/          # Kotlin code
│   │   │   └── jniLibs/       # Pre-built .so files
│   │   └── build.gradle.kts
│   └── gradlew                 # Gradle wrapper
├── scripts/                    # Build scripts
└── build/                      # Build artifacts (generated)
```

## Common Issues

### "ANDROID_NDK_ROOT not set"

The Nix shell should auto-detect your Android SDK/NDK. If it fails:

```bash
# Option 1: Set manually
export ANDROID_NDK_ROOT=/path/to/ndk

# Option 2: Install via Android Studio
# Tools → SDK Manager → SDK Tools → NDK
```

### "No devices found"

```bash
# Check ADB connection
adb devices

# Restart ADB server
adb kill-server
adb start-server

# Check USB debugging is enabled on device
```

### "zig: command not found"

```bash
# You must be in the nix-shell
nix-shell

# Then run make
make android
```

### Build Cache Issues

```bash
# Clean everything and rebuild
make clean
make android
```

## Makefile Targets Reference

Run `make help` to see all available commands:

| Command | Description |
|---------|-------------|
| `make android` | **[Main]** Build native + APK + install |
| `make setup` | Clone Ghostty submodule |
| `make check-env` | Verify environment variables |
| `make build-native` | Build all Android ABIs |
| `make build-android` | Build APK only |
| `make install` | Install APK to device |
| `make clean` | Clean build artifacts |
| `make clean-all` | Clean everything including submodule |

## What Gets Built

### Native Libraries (C/Zig)

- `libghostty-vt.so` - Ghostty VT parser (1.5MB per ABI)
- `libghostty_bridge.so` - JNI wrapper (compiled by CMake)

Located in: `android/app/src/main/jniLibs/{abi}/`

### Android APK

- **Debug APK**: `android/app/build/outputs/apk/debug/app-debug.apk`
- **Size**: ~5-10MB (includes all ABIs)

## Development Workflow

### 1. Initial Setup

```bash
git clone <your-repo>
cd ghostty-android
nix-shell
make android
```

### 2. Make Changes to Kotlin Code

```bash
# No need to rebuild native libraries
cd android
./gradlew installDebug
```

### 3. Make Changes to JNI Code (C)

```bash
# Rebuild JNI bridge and reinstall
cd android
./gradlew installDebug
```

### 4. Make Changes to libghostty-vt

```bash
# Rebuild native libraries
make build-native
cd android
./gradlew installDebug
```

## Next Steps

- Read `android/README.md` for Android app architecture
- Check `docs/ARCHITECTURE.md` for overall design
- See `STATUS.md` for project roadmap

## Getting Help

- Check logs: `adb logcat | grep Ghostty`
- Run diagnostics: `make check-env`
- Clean build: `make clean && make android`
- File issues on GitHub

---

**Quick tip**: Bookmark this command for development:

```bash
make clean && make android && adb logcat -c && adb logcat | grep -E "(Ghostty|Terminal)"
```

This cleans, rebuilds, installs, and immediately shows logs.
