# Ghostty Android

A high-performance, GPU-accelerated terminal emulator for Android using libghostty-vt for terminal parsing and Jetpack Compose Canvas for hardware-accelerated rendering.

## Project Vision

This project aims to bring desktop-class terminal emulation performance to Android by combining:

- **libghostty-vt**: State-of-the-art terminal sequence parsing from [Ghostty](https://github.com/ghostty-org/ghostty)
- **Native Performance**: Zero-dependency Zig library cross-compiled for Android ARM64
- **GPU Acceleration**: Hardware-accelerated rendering using Jetpack Compose Canvas
- **Modern Architecture**: Kotlin + Jetpack Compose UI with JNI bridge to native code

## Why This Project?

Current Android terminal emulators typically use:
- JavaScript-based parsing (xterm.js in WebView) - slower, higher memory usage
- CPU-based text rendering - limited performance on complex terminal output
- Older, less maintained codebases

**Ghostty Android provides:**
- ✅ **Native terminal parsing** - SIMD-optimized VT sequence processing
- ✅ **GPU-accelerated rendering** - Smooth 60fps+ even with heavy output
- ✅ **Small binary size** - Zero-dependency libghostty-vt core
- ✅ **Modern codebase** - Written in Zig and Kotlin with active development
- ✅ **Feature-complete** - Supports advanced terminal features (Kitty Graphics Protocol, tmux control mode)

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Android App (Kotlin + Jetpack Compose)             │
│  ┌─────────────────────────────────────────────┐   │
│  │  GPU Renderer (Compose Canvas)              │   │
│  │  - Hardware-accelerated text rendering      │   │
│  │  - RenderThread optimization                │   │
│  │  - Efficient redraws (dirty regions)        │   │
│  └─────────────────────────────────────────────┘   │
│                      ↕ JNI                          │
│  ┌─────────────────────────────────────────────┐   │
│  │  libghostty-vt (Zig → Native ARM64)         │   │
│  │  - Terminal sequence parsing                │   │
│  │  - Terminal state management                │   │
│  │  - Grid/scrollback buffer                   │   │
│  │  - Zero dependencies (no libc)              │   │
│  └─────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

## Project Status

**Current Phase: Research & Planning**

- [x] Research libghostty-vt architecture
- [x] Evaluate Android GPU rendering options
- [x] Define project goals and architecture
- [ ] Set up Zig cross-compilation for Android
- [ ] Clone and build libghostty-vt
- [ ] Create JNI wrapper for libghostty-vt C API
- [ ] Implement basic Jetpack Compose terminal renderer
- [ ] Handle Android input (touch, keyboard)
- [ ] Performance benchmarking vs existing solutions
- [ ] Polish and release v1.0

## Technology Stack

### Native Layer (libghostty-vt)
- **Language**: Zig (cross-compiled to ARM64/ARMv7)
- **Library**: libghostty-vt from [ghostty](https://github.com/ghostty-org/ghostty)
- **Features**:
  - Zero-dependency terminal parser
  - SIMD-optimized sequence processing
  - Comprehensive VT compatibility
  - Small binary footprint

### Android Layer
- **Language**: Kotlin
- **UI Framework**: Jetpack Compose
- **Rendering**: Compose Canvas with hardware layer
- **Build System**: Gradle with Android NDK
- **Minimum SDK**: Android 7.0 (API 24) - Vulkan support
- **Target SDK**: Android 14+ (API 34)

## Quick Start

**TL;DR - NixOS Users**:

```bash
nix-shell
make android-studio  # Opens Android Studio → Build → Build APK
```

**TL;DR - Standard Linux**:

```bash
nix-shell
make android  # One command to build and install
```

📖 **For detailed instructions, see [QUICK_START.md](QUICK_START.md)**
⚠️ **NixOS users**: See [NIXOS_BUILD.md](docs/NIXOS_BUILD.md) for AAPT2 solutions

## Building from Source

### Prerequisites

- **Nix** (recommended) - provides all dependencies automatically
- **OR** manual setup:
  - Android SDK and NDK (r29+)
  - Zig 0.15.2+
  - JDK 17+
  - Gradle 8.11+
- Android device with USB debugging enabled

### Build Steps

```bash
# Clone the repository
git clone https://github.com/yourusername/ghostty-android.git
cd ghostty-android

# Enter Nix development shell (recommended)
nix-shell

# NixOS: Use Android Studio
make android-studio

# Standard Linux: One-command build
make android

# Build libghostty-vt for Android
./scripts/build-native.sh

# Build and install Android app
cd android
./gradlew assembleDebug
adb install app/build/outputs/apk/debug/app-debug.apk
```

## Roadmap

### Phase 1: Foundation (Month 1-2)
- [ ] Set up cross-compilation for libghostty-vt
- [ ] Create JNI bindings
- [ ] Basic terminal rendering in Compose
- [ ] Handle keyboard and touch input

### Phase 2: Core Features (Month 2-3)
- [ ] Scrollback buffer support
- [ ] Text selection and clipboard
- [ ] Font customization
- [ ] Color scheme support
- [ ] Terminal resize handling

### Phase 3: Advanced Features (Month 3-4)
- [ ] Kitty Graphics Protocol support
- [ ] True color support
- [ ] Ligature rendering
- [ ] Performance optimizations
- [ ] Battery usage optimization

### Phase 4: Polish & Release (Month 4-5)
- [ ] UI/UX refinement
- [ ] Settings and customization
- [ ] Documentation
- [ ] Play Store release
- [ ] F-Droid release

## Performance Goals

Target metrics (measured on mid-range Android device):
- **Parsing throughput**: >10 MB/s of terminal output
- **Rendering FPS**: Consistent 60fps with heavy output (e.g., `cat large.log`)
- **Memory usage**: <50MB for typical terminal session
- **APK size**: <10MB
- **Startup time**: <500ms cold start

## Contributing

This is an open-source project welcoming contributions! Areas where help is needed:

- [ ] Zig/Android NDK cross-compilation expertise
- [ ] Android GPU rendering optimization
- [ ] Terminal emulation testing and bug reports
- [ ] Documentation and examples
- [ ] UI/UX design

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

This project is licensed under the MIT License - see [LICENSE](LICENSE) file.

**Note**: libghostty-vt is part of the Ghostty project and is licensed separately. See [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) for details.

## Acknowledgments

- [Ghostty](https://github.com/ghostty-org/ghostty) by Mitchell Hashimoto - for the excellent libghostty-vt library
- [Termux](https://github.com/termux/termux-app) - inspiration and reference for Android terminal implementation
- The Zig community for excellent cross-compilation support

## Related Projects

- [Ghostty](https://github.com/ghostty-org/ghostty) - The desktop terminal emulator this is based on
- [Termux](https://github.com/termux/termux-app) - Full-featured terminal for Android
- [ConnectBot](https://github.com/connectbot/connectbot) - Secure shell client for Android

## Contact

- **Issues**: [GitHub Issues](https://github.com/yourusername/ghostty-android/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/ghostty-android/discussions)

---

**Status**: Early development - not yet usable. Watch this repository for updates!
