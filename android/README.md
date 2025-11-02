# Ghostty Android App

Android terminal emulator powered by libghostty-vt.

## Project Structure

```
android/
├── app/
│   ├── src/
│   │   └── main/
│   │       ├── cpp/                    # JNI bridge (C)
│   │       │   ├── ghostty_bridge.c   # JNI wrapper for libghostty-vt
│   │       │   └── CMakeLists.txt     # CMake build configuration
│   │       ├── java/com/ghostty/android/
│   │       │   ├── MainActivity.kt    # Main activity
│   │       │   ├── terminal/
│   │       │   │   ├── GhosttyBridge.kt    # Kotlin JNI interface
│   │       │   │   └── TerminalSession.kt  # Shell process manager
│   │       │   └── ui/
│   │       │       ├── TerminalView.kt     # Terminal display (Compose)
│   │       │       ├── InputToolbar.kt     # Input toolbar
│   │       │       └── theme/              # Material3 theme
│   │       ├── jniLibs/
│   │       │   └── arm64-v8a/
│   │       │       └── libghostty-vt.so   # Pre-built native library
│   │       ├── res/                   # Android resources
│   │       └── AndroidManifest.xml
│   └── build.gradle.kts               # App Gradle configuration
├── gradle/                            # Gradle wrapper
├── build.gradle.kts                   # Root Gradle configuration
├── settings.gradle.kts                # Gradle settings
└── gradlew                            # Gradle wrapper script
```

## Building

### Prerequisites

1. Android SDK (API level 24+)
2. Android NDK (r29+)
3. Gradle 8.11+
4. Java 17+

The native library (`libghostty-vt.so`) must be built first using the root Makefile.

### Build Native Libraries

From the project root:

```bash
# Build for ARM64
make build-abi ABI=arm64-v8a

# Build for all ABIs
make build-native
```

### Build Android App

```bash
cd android

# Build debug APK
./gradlew assembleDebug

# Build release APK
./gradlew assembleRelease

# Install on connected device
./gradlew installDebug
```

## Architecture

### Native Layer (JNI)

- **ghostty_bridge.c**: JNI wrapper that exposes libghostty-vt functions to Kotlin
  - Key encoding (keyboard events → VT sequences)
  - Paste safety validation
  - OSC/SGR parsing utilities

### Kotlin Layer

- **GhosttyBridge**: Singleton wrapper around JNI functions
- **TerminalSession**: Manages shell process (stdin/stdout)
- **TerminalView**: Jetpack Compose UI for terminal display
- **InputToolbar**: Quick-access toolbar for special keys

### UI (Jetpack Compose)

- Material3 design with dark terminal theme
- Monospace text rendering via Canvas
- Scroll support for terminal output
- Software keyboard integration
- Touch-to-focus terminal input

## Features

### Current (v0.1.0)

- [x] Basic terminal UI with Jetpack Compose
- [x] Shell process management
- [x] libghostty-vt JNI integration
- [x] Key encoder for VT sequences
- [x] Paste safety validation
- [x] Basic terminal colors (Catppuccin theme)
- [x] Scrollable output
- [x] Input toolbar with common keys

### Planned

- [ ] Full VT parser integration (requires upstream C API)
- [ ] Advanced text rendering (colors, attributes, cursor)
- [ ] Terminal grid state management
- [ ] Text selection and copy
- [ ] Kitty graphics protocol
- [ ] Custom fonts
- [ ] Configurable color schemes
- [ ] Split screen / multiple sessions

## Limitations

Currently, the app uses a simplified architecture because libghostty-vt's full Terminal/Parser is not exposed via C API. The available C APIs provide:

- Key event encoding
- OSC command parsing
- SGR attribute parsing
- Paste validation

To enable full VT parsing and rendering, we would need to either:

1. Contribute C API wrappers for `Terminal` and `Screen` to libghostty-vt
2. Create Zig JNI bindings directly
3. Use an external VT parser library

## Development

### Opening in Android Studio

1. Open Android Studio
2. Select "Open" → Choose the `android/` directory
3. Wait for Gradle sync
4. Select a device/emulator
5. Click "Run"

### Debugging

Enable debug logs:

```bash
adb logcat | grep -E "(GhosttyBridge|TerminalSession|MainActivity)"
```

### Testing

```bash
# Run unit tests
./gradlew test

# Run instrumented tests
./gradlew connectedAndroidTest
```

## License

MIT License (same as parent project)
