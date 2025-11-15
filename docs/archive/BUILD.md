# Building Ghostty Android

This document explains how to build Ghostty Android from source.

## Prerequisites

### Required Tools

1. **Zig** (0.11.0 or later)
   ```bash
   # Download from https://ziglang.org/download/
   # Or install via package manager
   curl -L https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz | tar -xJ
   sudo mv zig-linux-x86_64-0.13.0 /opt/zig
   export PATH=/opt/zig:$PATH
   ```

2. **Android Studio** (Latest stable)
   - Download from https://developer.android.com/studio
   - Install Android SDK Platform 34
   - Install Android NDK r25 or later

3. **Android NDK**
   ```bash
   # Install via Android Studio SDK Manager
   # Or download directly from:
   # https://developer.android.com/ndk/downloads
   export ANDROID_NDK_HOME=$HOME/Android/Sdk/ndk/25.2.9519653
   ```

4. **JDK 17 or later**
   ```bash
   # Check your Java version
   java -version

   # Install if needed (Ubuntu/Debian)
   sudo apt install openjdk-17-jdk
   ```

5. **Git** (for cloning submodules)
   ```bash
   sudo apt install git
   ```

## Quick Start

```bash
# Clone with submodules
git clone --recursive https://github.com/yourusername/ghostty-android.git
cd ghostty-android

# Build native library
./scripts/build-native.sh

# Build and install Android app
cd android
./gradlew assembleDebug
adb install app/build/outputs/apk/debug/app-debug.apk
```

## Detailed Build Steps

### 1. Clone the Repository

```bash
# Clone with submodules (includes libghostty-vt)
git clone --recursive https://github.com/yourusername/ghostty-android.git
cd ghostty-android

# If you already cloned without --recursive
git submodule update --init --recursive
```

### 2. Build libghostty-vt for Android

The native library needs to be cross-compiled for Android ARM architectures.

```bash
# Set up Android NDK path
export ANDROID_NDK_HOME=$HOME/Android/Sdk/ndk/25.2.9519653

# Build for all architectures (arm64-v8a, armeabi-v7a, x86_64)
./scripts/build-native.sh

# Or build for specific architecture
./scripts/build-native.sh arm64-v8a
```

This script will:
1. Extract libghostty-vt from the Ghostty repository
2. Create Zig build configuration for Android
3. Cross-compile for ARM64, ARMv7, and x86_64
4. Place resulting `.so` files in `android/app/src/main/jniLibs/`

### 3. Build Android Application

```bash
cd android

# Debug build
./gradlew assembleDebug

# Release build (requires signing configuration)
./gradlew assembleRelease
```

Output APKs will be in:
- Debug: `android/app/build/outputs/apk/debug/app-debug.apk`
- Release: `android/app/build/outputs/apk/release/app-release.apk`

### 4. Install on Device

```bash
# Connect device via USB or wireless ADB
adb devices

# Install debug APK
adb install app/build/outputs/apk/debug/app-debug.apk

# Or use Gradle
./gradlew installDebug
```

## Build Variants

### Debug Build
- Includes debugging symbols
- No optimization
- Larger APK size
- Easier to debug with Android Studio

```bash
./gradlew assembleDebug
```

### Release Build
- Optimized native code
- ProGuard/R8 minification
- Requires signing configuration

```bash
./gradlew assembleRelease
```

## Architecture-Specific Builds

Build for specific CPU architectures to reduce APK size:

```bash
# ARM64 only (modern devices)
./gradlew assembleDebug -PabiFilters=arm64-v8a

# ARMv7 only (older devices)
./gradlew assembleDebug -PabiFilters=armeabi-v7a

# x86_64 only (emulators, some tablets)
./gradlew assembleDebug -PabiFilters=x86_64
```

## Development Builds

### Hot Reload with Android Studio

1. Open the `android/` directory in Android Studio
2. Connect device/emulator
3. Click Run (Shift+F10)
4. Make changes to Kotlin code
5. Use Apply Changes (Ctrl+F10) for instant updates

**Note**: Native library changes require full rebuild.

### Incremental Native Builds

```bash
# Only rebuild if native code changed
./scripts/build-native.sh --incremental

# Force clean rebuild
./scripts/build-native.sh --clean
```

## Testing

### Unit Tests

```bash
cd android
./gradlew test
```

### Instrumented Tests (requires device/emulator)

```bash
cd android
./gradlew connectedAndroidTest
```

### Manual Testing

```bash
# Install and launch
./gradlew installDebug
adb shell am start -n com.ghostty.android/.MainActivity

# View logs
adb logcat -c && adb logcat | grep -E "Ghostty|GhosttyVT"
```

## Troubleshooting

### NDK Not Found

```bash
# Set NDK path explicitly
export ANDROID_NDK_HOME=/path/to/ndk
./scripts/build-native.sh
```

### Zig Build Fails

```bash
# Check Zig version
zig version  # Should be 0.11.0+

# Verify NDK libc.txt is correct
cat android/ndk-libc.txt
```

### JNI Library Not Found

```bash
# Verify .so files are in correct location
ls -R android/app/src/main/jniLibs/

# Should show:
# arm64-v8a/libghostty_vt.so
# armeabi-v7a/libghostty_vt.so
# x86_64/libghostty_vt.so
```

### Gradle Sync Issues

```bash
# Clean and rebuild
cd android
./gradlew clean
./gradlew build --refresh-dependencies
```

### ABI Compatibility Issues

If app crashes on device:

```bash
# Check device ABI
adb shell getprop ro.product.cpu.abi

# Build for that specific ABI
./scripts/build-native.sh <abi>
```

## Performance Optimization

### Native Library Optimization

Edit `build.zig` to adjust optimization:

```zig
const mode = if (optimize) .ReleaseFast else .Debug;
```

Build with optimization:
```bash
./scripts/build-native.sh --release
```

### APK Size Reduction

```bash
# Enable ProGuard/R8
./gradlew assembleRelease

# Enable APK splitting by ABI
# Edit android/app/build.gradle:
splits {
    abi {
        enable true
        reset()
        include 'arm64-v8a', 'armeabi-v7a'
    }
}
```

## Clean Build

```bash
# Clean everything
./scripts/clean.sh

# Or manually
rm -rf android/app/src/main/jniLibs/
rm -rf android/build/
rm -rf android/app/build/
rm -rf zig-cache/
rm -rf zig-out/
```

## CI/CD Builds

For automated builds (GitHub Actions, etc.):

```yaml
# .github/workflows/build.yml
- name: Set up Zig
  uses: goto-bus-stop/setup-zig@v2
  with:
    version: 0.13.0

- name: Set up Android NDK
  run: |
    echo "y" | sdkmanager "ndk;25.2.9519653"

- name: Build native library
  run: ./scripts/build-native.sh

- name: Build APK
  run: |
    cd android
    ./gradlew assembleRelease
```

## Next Steps

After successfully building:
1. Read [ARCHITECTURE.md](ARCHITECTURE.md) to understand the codebase
2. Check [CONTRIBUTING.md](../CONTRIBUTING.md) for development guidelines
3. Run the test suite to verify your build
4. Start developing!

---

**Having issues?** Open an issue on GitHub with:
- Your OS and version
- Zig version (`zig version`)
- NDK version
- Full error output
