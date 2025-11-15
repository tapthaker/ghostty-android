# Ghostty Android - Testing Guide

Visual regression testing system for Ghostty Android terminal renderer.

## Quick Start

```bash
nix-shell
make test-feedback-list                         # List all tests
make test-feedback-id TEST_ID=text_attributes   # Run specific test
make test-feedback                              # Run all tests (interactive)
```

## Testing System

**Script:** `test_feedback_loop.py` (project root)

**Purpose:** Interactive visual testing with manual verification

**How it works:**
1. Launches app with test ID via ADB intent
2. Monitors logcat for test completion signals
3. Captures screenshot from device
4. Interactive verification (pass/fail/skip/quit)
5. Saves results and screenshots

**Requirements:**
- Device connected via ADB
- App installed (`make android`)
- Python 3 in nix-shell

## Available Tests (20 total)

### Color Rendering
- `basic_colors_fg` - 8 basic ANSI foreground colors
- `basic_colors_bg` - 8 basic ANSI background colors
- `256_colors` - Extended 256-color palette
- `rgb_colors` - True color (24-bit RGB)

### Text Attributes
- `text_attributes` - Bold, italic, underline, strikethrough
- `combined_attributes` - Multiple attributes simultaneously

### Cursor & Movement
- `cursor_position` - Absolute cursor positioning
- `cursor_movement` - Relative cursor movement

### Screen Operations
- `screen_clear` - Clear screen/line operations
- `line_operations` - Insert/delete line operations
- `scrollback` - Scrollback buffer behavior

### Line Wrapping
- `line_wrap_basic` - Basic line wrapping
- `line_wrap_word_boundary` - Word-boundary wrapping
- `line_wrap_ansi_colors` - Wrapping with ANSI colors

### Unicode & Special Characters
- `utf8_basic` - Basic UTF-8 text
- `emoji` - Emoji rendering (wide characters)
- `box_drawing` - Box-drawing characters
- `special_chars` - Special symbols
- `double_width` - Double-width CJK characters
- `combining_chars` - Combining diacritics

## Running Tests

### List Available Tests
```bash
make test-feedback-list
```

### Run Specific Test
```bash
make test-feedback-id TEST_ID=text_attributes
```

**Example workflow:**
```
============================================================
  LAUNCHING TEST: text_attributes
============================================================

✓ Stopped existing app instance
✓ App launched with test
⏱  Monitoring test execution (timeout: 30s)...
  ▶  Test started
  📸 Test ready for screenshot
  ✓  Test completed

📸 Capturing screenshot...
✓ Screenshot saved: /tmp/feedback_tests/screenshots/text_attributes.png

============================================================
  VERIFY TEST: text_attributes
============================================================

Does the test PASS? (y/n/skip/quit): y

✅ Test text_attributes PASSED
```

### Run From Specific Test
```bash
make test-feedback-from FROM=256_colors
```

Use to resume after fixing issues or skip already-passed tests.

### Run All Tests
```bash
make test-feedback
```

Runs tests sequentially with interactive verification for each.

### Direct Script Usage

For custom output directory:
```bash
python3 test_feedback_loop.py --test-id text_attributes
python3 test_feedback_loop.py --start-from 256_colors
python3 test_feedback_loop.py --output /custom/output/dir
```

## Test Output

**Location:** `/tmp/feedback_tests/`

```
/tmp/feedback_tests/
├── test_results.json       # Test results and status
└── screenshots/
    ├── basic_colors_fg.png
    ├── text_attributes.png
    └── ...
```

**test_results.json format:**
```json
{
  "text_attributes": {
    "status": "PASSED",
    "screenshot": "/tmp/feedback_tests/screenshots/text_attributes.png",
    "timestamp": "2025-11-15 08:30:45"
  },
  "256_colors": {
    "status": "FAILED",
    "screenshot": "/tmp/feedback_tests/screenshots/256_colors.png",
    "timestamp": "2025-11-15 08:31:12",
    "notes": "Colors 16-31 not rendering correctly"
  }
}
```

## Testing Workflow

### 1. Full Build and Test
```bash
nix-shell
make android                                    # Build + install
make test-feedback-id TEST_ID=text_attributes   # Test feature
```

### 2. Fix and Verify
```bash
# Make code changes
make build-native    # If renderer/native code changed
make build-android   # If Kotlin code changed
make install

# Re-test
make test-feedback-id TEST_ID=text_attributes
```

### 3. Systematic Testing
```bash
# Test incrementally
make test-feedback-id TEST_ID=basic_colors_fg  # Pass
make test-feedback-id TEST_ID=256_colors       # Fail - fix issue
make test-feedback-from FROM=256_colors        # Resume from failure
```

## Verification Guidelines

When reviewing screenshots, check:

**Color Accuracy:**
- ANSI colors match expected values
- No color bleeding or artifacts
- Proper foreground/background separation

**Text Rendering:**
- Text is clear and readable
- Correct font rendering
- Proper character positioning

**Attributes:**
- Bold is visibly bolder
- Italic is slanted
- Underline is present and correct
- Strikethrough works

**Layout:**
- Cursor in correct position
- Line wrapping at boundaries
- No unexpected line breaks
- Scrollback preserves content

**Special Characters:**
- Unicode renders correctly
- Emoji displays properly
- Box drawing characters align
- Double-width characters occupy correct space

## Debugging Failed Tests

### Check Logs
```bash
make logs
# Or
adb logcat -s TestRunner:I GhosttyRenderer:I
```

### Common Issues

**Colors not rendering:**
- Check shader uniforms in `android/renderer/src/shaders/glsl/cell_text.f.glsl`
- Verify screen data extraction in `screen_extractor.zig`

**Text not visible:**
- Check font loading in `font_system.zig`
- Verify glyph rendering in `renderer.zig`

**Attributes not working:**
- Check attribute flags in screen extraction
- Verify shader attribute handling

**App crashes:**
```bash
adb logcat -d | grep -E "(FATAL|ERROR)"
```

**Test timeout:**
- Check `make logs` for errors
- Ensure device is unlocked
- Verify test is running: `adb logcat -s TestRunner:I`

## Manual Testing (Advanced)

For manual control:

```bash
# Launch specific test
adb shell am start -n com.ghostty.android/.MainActivity \
  --ez AUTO_START_TESTS true \
  --es TEST_ID text_attributes

# Capture screenshot
adb exec-out screencap -p > /tmp/test.png

# Check test status
adb logcat -s TestRunner:I
```

## Test Implementation

Tests are defined in Android app:
- `android/app/src/main/java/com/ghostty/android/testing/TestSuite.kt` - Test definitions
- `android/app/src/main/java/com/ghostty/android/testing/TestRunner.kt` - Test execution

Test flow:
1. App receives test ID via intent
2. Test writes VT sequences to terminal
3. Terminal processes and renders
4. Test signals completion via logcat
5. Script captures screenshot
6. User verifies result

## Success Criteria

A test passes when:
- ✅ Screenshot matches expected visual output
- ✅ No crashes or errors in logs
- ✅ Test completes with success signal
- ✅ All colors/attributes/characters render correctly
- ✅ Layout and positioning are accurate

## Future Enhancements

Planned improvements:
- Reference image comparison (automated pass/fail)
- Headless testing for CI/CD
- HTML test reports
- Parallel test execution
- Test coverage metrics

## Related Documentation

- [BUILD_GUIDE.md](BUILD_GUIDE.md) - Build instructions
- [RENDERER_ARCHITECTURE.md](RENDERER_ARCHITECTURE.md) - Renderer internals
- [test_feedback_loop.py](../test_feedback_loop.py) - Test script source
