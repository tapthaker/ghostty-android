# Ghostty Android - AI Assistant Guide

Quick reference for Claude Code working with Ghostty Android.

## Critical Rules

1. **ALWAYS run `nix-shell` first** - All commands require nix-shell environment
2. **Use `make` targets** - Don't call scripts directly (Makefile has automatic checks)
3. **Check `make help`** - Shows all available targets and configuration

## Quick Commands

```bash
# Build & Deploy
make android          # Build + install + launch (one command)
make build-native     # Build native libs only
make build-android    # Build APK only
make logs             # View app logs

# Testing
make test-feedback-list              # List test IDs
make test-feedback-id TEST_ID=<id>   # Run specific test
make test-feedback                   # Run all tests (interactive)

# Maintenance
make clean       # Clean build artifacts
make clean-all   # Clean everything
```

## Essential Info

**Build System:**
- Makefile orchestrates everything
- Two nix-shells: project (Android/Java) + Ghostty (Zig)
- Auto-detects if not in nix-shell and shows error

**Test IDs:** basic_colors_fg, basic_colors_bg, 256_colors, rgb_colors, text_attributes, combined_attributes, cursor_position, cursor_movement, screen_clear, line_operations, scrollback, line_wrap_basic, line_wrap_word_boundary, line_wrap_ansi_colors, utf8_basic, emoji, box_drawing, special_chars, double_width, combining_chars

**Output:**
- Native libs: `android/app/src/main/jniLibs/<ABI>/`
- APK: `android/app/build/outputs/apk/debug/app-debug.apk`
- Test results: `/tmp/feedback_tests/`

## Documentation Reference

**For detailed information, see `docs/`:**

### Build & Setup
- [docs/BUILD.md](docs/BUILD.md) - Comprehensive build instructions
- [docs/BUILD_SETUP.md](docs/BUILD_SETUP.md) - Initial setup and dependencies
- [docs/NIXOS_BUILD.md](docs/NIXOS_BUILD.md) - NixOS-specific build notes
- [docs/BUILD_SUCCESS.md](docs/BUILD_SUCCESS.md) - Build success checklist

### Testing
- [docs/VISUAL_TESTING_SETUP.md](docs/VISUAL_TESTING_SETUP.md) - Visual test framework setup
- [docs/VISUAL_TESTING_FEEDBACK_LOOP.md](docs/VISUAL_TESTING_FEEDBACK_LOOP.md) - Feedback loop testing guide
- [test_feedback_loop.py](test_feedback_loop.py) - Test script (project root)

### Renderer & Architecture
- [docs/RENDERER_ARCHITECTURE.md](docs/RENDERER_ARCHITECTURE.md) - Renderer design and implementation
- [docs/RENDERER_QUICK_REFERENCE.md](docs/RENDERER_QUICK_REFERENCE.md) - Renderer API reference
- [docs/RENDERER_STATUS.md](docs/RENDERER_STATUS.md) - Current renderer status
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - Overall project architecture
- [docs/text-attributes-implementation.md](docs/text-attributes-implementation.md) - Text attributes rendering

### Analysis & Investigation
- [docs/OPENGL_RENDERER_ANALYSIS.md](docs/OPENGL_RENDERER_ANALYSIS.md) - OpenGL renderer analysis
- [docs/OPENGL_ANALYSIS_INDEX.md](docs/OPENGL_ANALYSIS_INDEX.md) - OpenGL analysis index

### Project Status
- [docs/STATUS.md](docs/STATUS.md) - Current project status
- [docs/PROGRESS.md](docs/PROGRESS.md) - Development progress tracking

### Getting Started (Root Level)
- [README.md](README.md) - Project overview
- [QUICK_START.md](QUICK_START.md) - Quick start guide
- [CONTRIBUTING.md](CONTRIBUTING.md) - Contribution guidelines

## Common Patterns

**Full workflow:**
```bash
nix-shell
make android                              # Build + install
make test-feedback-id TEST_ID=text_attributes  # Test
```

**Incremental rebuild:**
```bash
nix-shell
make build-native    # If Zig code changed
make build-android   # If Kotlin code changed
make install
```

**DO ✓**
- Work in nix-shell
- Use make targets
- Call gradle from `android/` dir: `cd android && ./gradlew ...`

**DON'T ✗**
- Run make outside nix-shell
- Call `./scripts/build-*.sh` directly
- Run gradle from project root
