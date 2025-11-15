# Ghostty Android - Build System Guide

Quick reference for AI assistants working with the Ghostty Android build system.

## Critical Rules

1. **ALWAYS work inside `nix-shell`** - Run `nix-shell` first, then execute commands
2. **Use `make` targets** - Don't call build scripts directly
3. **Check `make help`** - Shows all targets and current configuration

## Build System Architecture

- **Makefile-based** build orchestration
- **Two-layer Nix environments:**
  - Project `shell.nix`: Android SDK/NDK, JDK17, build tools
  - Ghostty `libghostty-vt/shell.nix`: Zig 0.15.2 for native builds
- **Automatic nix-shell detection**: Commands fail with clear error if not in nix-shell

## Essential Commands

### Build & Deploy
```bash
make help             # Show all targets
make android          # Build + install + launch (one command does everything)
make build-native     # Build native libs (libghostty-vt + renderer)
make build-android    # Build Android APK
make install          # Install to device
make logs             # View app logs
```

### Testing
```bash
make test-feedback-list              # List all test IDs
make test-feedback-id TEST_ID=<id>   # Run specific test
make test-feedback-from FROM=<id>    # Run from test onwards
make test-feedback                   # Run all tests (interactive)
```

Available test IDs: `basic_colors_fg`, `basic_colors_bg`, `256_colors`, `rgb_colors`, `text_attributes`, `combined_attributes`, `cursor_position`, `cursor_movement`, `screen_clear`, `line_operations`, `scrollback`, `line_wrap_basic`, `line_wrap_word_boundary`, `line_wrap_ansi_colors`, `utf8_basic`, `emoji`, `box_drawing`, `special_chars`, `double_width`, `combining_chars`

### Maintenance
```bash
make clean       # Clean build artifacts
make clean-all   # Clean everything including Ghostty submodule
```

## Common Workflows

**Full build and test:**
```bash
nix-shell
make android                              # Build + install + launch
make test-feedback-id TEST_ID=text_attributes  # Test specific feature
```

**Incremental rebuild:**
```bash
nix-shell
make build-native    # If Zig/native code changed
make build-android   # If Kotlin/Android code changed
make install         # Install updated APK
```

**Development with Android Studio:**
```bash
nix-shell
make android-studio  # Opens with proper environment
```

## Build Scripts (For Reference)

Don't call these directly - use `make` targets instead:
- `scripts/build-android-abi.sh <ABI> <OUTPUT>` - Builds native libs for one ABI
- `android/scripts/build-android.sh [--install]` - Builds APK

## Command Execution Rules

### DO ✓
```bash
# In nix-shell
make android
make build-native
cd android && ./gradlew assembleDebug   # Gradle OK from android/ dir
adb devices                             # ADB commands work directly
```

### DON'T ✗
```bash
make android                            # Without nix-shell first
./scripts/build-android-abi.sh ...      # Don't call scripts directly
./gradlew assembleDebug                 # Wrong directory (use android/)
```

## ABI Targets

| Android ABI | Zig Target | Use Case |
|-------------|------------|----------|
| arm64-v8a | aarch64-linux-android | Modern ARM 64-bit |
| armeabi-v7a | arm-linux-androideabi | Older ARM 32-bit |
| x86_64 | x86_64-linux-android | Emulators |

Output: `android/app/src/main/jniLibs/<ABI>/`

## Testing System

**Script:** `test_feedback_loop.py` (project root)
**How it works:**
1. Launches app with test ID via ADB
2. Monitors logcat for completion
3. Captures screenshot
4. Interactive verification (pass/fail/skip)
5. Saves results to `/tmp/feedback_tests/`

**Requirements:** Device connected, app installed, Python 3

## Troubleshooting

**Not in nix-shell?** → Error box appears with instructions
**ANDROID_HOME not set?** → Enter `nix-shell` first
**Gradle AAPT2 errors?** → Make sure you're in `nix-shell`
**Libraries missing in APK?** → Run `make build-native` before `make build-android`

## Key Takeaways

1. **Always use nix-shell** - Makefile checks automatically
2. **Use make targets** - Scripts called directly will fail
3. **Build order**: native libs → Android APK
4. **One-stop command**: `make android` does everything
5. **Test script location**: `test_feedback_loop.py` in project root
6. **Gradle from android/ only**: If calling directly, must `cd android` first
