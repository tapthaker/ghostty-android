# Visual Testing Feedback Loop

This document describes the systematic approach to visual regression testing for Ghostty Android.

## Overview

The feedback loop is a systematic process to verify each visual test, identify rendering bugs, fix them, and iterate until all tests pass.

## The Feedback Loop Process

### 1. Run Test
Launch the app with a specific test ID:
```bash
adb shell am start -S -n com.ghostty.android/.MainActivity --es TEST_ID <test_id>
```

### 2. Capture Screenshot
Wait for test completion, then capture:
```bash
sleep 3
adb exec-out screencap -p > /tmp/test_<test_id>.png
```

### 3. Analyze Screenshot
Review the screenshot for:
- **Color accuracy**: Are ANSI colors rendering correctly?
- **Text rendering**: Is text clear and positioned correctly?
- **Attributes**: Are bold, italic, underline, etc. working?
- **Cursor positioning**: Is the cursor in the right place?
- **Line wrapping**: Does text wrap properly?
- **Special characters**: Do Unicode, emoji, box drawing render correctly?

### 4. Identify Bugs
Common issues to look for:
- Colors not matching expected values
- Text not rendering (blank screen)
- Incorrect font rendering
- Missing attributes (bold, italic, etc.)
- Cursor positioning errors
- Incorrect line wrapping
- Character encoding issues
- Crashes or exceptions in logs

### 5. Fix Bugs
Depending on the issue:
- **Renderer issues**: Check `android/renderer/src/renderer.zig`
- **Font issues**: Check `android/renderer/src/font_system.zig`
- **Screen extraction**: Check `android/renderer/src/screen_extractor.zig`
- **Test definitions**: Check `android/app/src/main/java/com/ghostty/android/testing/TestSuite.kt`
- **Test execution**: Check `android/app/src/main/java/com/ghostty/android/testing/TestRunner.kt`

### 6. Verify Fix
After making changes:
```bash
# Rebuild
./android/scripts/build-android.sh

# Install
adb install -r android/app/build/outputs/apk/debug/app-debug.apk

# Re-run test
adb shell am start -S -n com.ghostty.android/.MainActivity --es TEST_ID <test_id>

# Capture new screenshot
adb exec-out screencap -p > /tmp/test_<test_id>_fixed.png
```

### 7. Continue Loop
- If test passes → Move to next test
- If test still fails → Return to step 4 (identify and fix)

## Test Categories

### Color Tests
- `basic_colors_fg` - 16 foreground colors
- `basic_colors_bg` - 16 background colors
- `256_colors` - 256 color palette
- `rgb_colors` - 24-bit RGB true color

### Attribute Tests
- `text_attributes` - Bold, italic, underline, etc.
- `combined_attributes` - Multiple attributes together

### Cursor Tests
- `cursor_position` - Absolute cursor positioning
- `cursor_movement` - Relative cursor movement

### Screen Control Tests
- `screen_clear` - Screen clearing
- `line_operations` - Line clearing and editing

### Line Wrapping Tests
- `line_wrap_basic` - Basic wrapping
- `line_wrap_word_boundary` - Word wrapping
- `line_wrap_ansi_colors` - Wrapping with colors
- `scrollback` - Scrollback buffer

### Character Set Tests
- `utf8_basic` - UTF-8 characters
- `emoji` - Emoji rendering
- `box_drawing` - Box drawing characters
- `special_chars` - Special characters
- `double_width` - Double-width CJK
- `combining_chars` - Combining diacritics

## Debugging Tools

### Check Logs
```bash
adb logcat -s TestRunner:I MainActivity:I TestModeScreen:I GhosttyRenderer:I
```

### Check for Errors
```bash
adb logcat -d | grep -E "(FATAL|ERROR|crash)"
```

### Monitor Test Execution
```bash
adb logcat -c
adb shell am start -n com.ghostty.android/.MainActivity --es TEST_ID <test_id>
adb logcat -s TestRunner:I
```

## Success Criteria

A test passes when:
- ✅ Screenshot matches expected visual output
- ✅ No crashes or errors in logs
- ✅ Test completes with PASSED status
- ✅ All colors/attributes/characters render correctly

## Automated Testing (Future)

For CI/CD integration:
```bash
python run_visual_tests.py --output ./test_results --test <test_id>
```

This will:
1. Launch the test
2. Capture screenshots automatically
3. Generate HTML report with results
