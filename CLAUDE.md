# Ghostty Android - AI Assistant Guide

Quick reference for Claude Code working with Ghostty Android.

## Critical Rules

1. **Use `command nix-shell --command "make ..."` to run commands** - This bypasses zsh-nix-shell plugin issues
2. **Use `make` targets** - Don't call scripts directly (Makefile has automatic checks)
3. **Check `make help`** - Shows all available targets and configuration

## Running Commands (Important!)

The system uses zsh-nix-shell plugin which can interfere with `nix-shell --command`. Always use:

```bash
# Correct way to run make commands
command nix-shell --command "make android"
command nix-shell --command "make test-feedback-id TEST_ID=text_attributes"

# DO NOT use (will fail with "buildShellShim" error):
nix-shell --command "make android"
```

The `command` prefix bypasses the zsh function wrapper and uses the actual nix-shell binary.

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

**Test IDs:** basic_colors_fg, basic_colors_bg, 256_colors, rgb_colors, text_attributes, combined_attributes, cursor_position, cursor_movement, cursor_visibility, cursor_styles, screen_clear, line_operations, scrollback, line_wrap_basic, line_wrap_word_boundary, line_wrap_ansi_colors, utf8_basic, emoji, box_drawing, special_chars, double_width, combining_chars

**Output:**
- Native libs: `android/app/src/main/jniLibs/<ABI>/`
- APK: `android/app/build/outputs/apk/debug/app-debug.apk`
- Test results: `/tmp/feedback_tests/`

## Documentation

**Essential Reading:**
- [docs/BUILD_GUIDE.md](docs/BUILD_GUIDE.md) - Complete build instructions
- [docs/TESTING.md](docs/TESTING.md) - Visual testing guide
- [docs/DEV_STATUS.md](docs/DEV_STATUS.md) - Current project status

**Architecture & Design:**
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - Overall architecture
- [docs/RENDERER_ARCHITECTURE.md](docs/RENDERER_ARCHITECTURE.md) - Renderer design
- [docs/RENDERER_QUICK_REFERENCE.md](docs/RENDERER_QUICK_REFERENCE.md) - Renderer API
- [docs/text-attributes-implementation.md](docs/text-attributes-implementation.md) - Text attributes

**Implementation Details:**
- [docs/RENDERER_STATUS.md](docs/RENDERER_STATUS.md) - Detailed renderer status
- [docs/BUILD_SUCCESS.md](docs/BUILD_SUCCESS.md) - Build success checklist

**Getting Started:**
- [README.md](README.md) - Project overview
- [QUICK_START.md](QUICK_START.md) - Quick start guide
- [CONTRIBUTING.md](CONTRIBUTING.md) - How to contribute

**Scripts:**
- [test_feedback_loop.py](test_feedback_loop.py) - Visual testing automation

## Common Patterns

**Full workflow:**
```bash
# Build, install, and launch the app
command nix-shell --command "make android"

# Run a specific visual test
command nix-shell --command "make test-feedback-id TEST_ID=text_attributes"
```

**Incremental rebuild:**
```bash
# If Zig code changed
command nix-shell --command "make build-native"

# If Kotlin code changed
command nix-shell --command "make build-android"

# Install to device
command nix-shell --command "make install"
```

**Capture screenshot:**
```bash
adb exec-out screencap -p > /tmp/screenshot.png
```

**DO ✓**
- Use `command nix-shell --command "make ..."` syntax
- Use make targets
- Call gradle from `android/` dir: `cd android && ./gradlew ...`

**DON'T ✗**
- Use bare `nix-shell --command` (zsh plugin breaks it)
- Call `./scripts/build-*.sh` directly
- Run gradle from project root
