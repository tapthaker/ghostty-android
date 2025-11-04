# Ghostty Android - Integrated Visual Regression Testing Framework

## Overview

This package provides an integrated testing framework for Ghostty Android that allows visual regression testing without requiring external Python orchestration or PTY/shell backend.

## Why This Approach?

As documented in `/tests/visual/FINDINGS.md`, the app currently lacks:
- PTY (pseudo-terminal) backend
- Shell integration
- Ability to execute terminal commands like `vttest`

Rather than waiting for these components, we've built a **native Android test framework** that:
- Injects ANSI escape sequences directly into the terminal emulator
- Tests the rendering layer without needing shell commands
- Runs entirely within the Android app
- Provides immediate visual feedback

## Current Limitations

**⚠️ IMPORTANT:** The test framework is currently **infrastructure-ready** but NOT rendering results visually due to the following architectural gap:

### The Problem

The current `TerminalSession` class writes input to a shell process (`/system/bin/sh`), but this is **NOT connected** to the Ghostty VT emulator or the OpenGL renderer. The data flow is incomplete:

```
Test ANSI sequences → TerminalSession.writeInput() → Shell stdin
                                                        ↓
                                                   (NOT rendered)

What's needed:
Test ANSI sequences → Ghostty VT Emulator → Screen Buffer → OpenGL Renderer → Display
```

### What Needs to be Done

To make the tests render visually, we need to:

1. **Connect TerminalSession to Ghostty VT Emulator**: The ANSI sequences need to be fed to `libghostty-vt` via JNI instead of to a shell process
2. **Update Screen Buffer**: The VT emulator needs to update an in-memory screen buffer
3. **Trigger GL Rendering**: The OpenGL renderer (`GhosttyGLSurfaceView`) needs to read from that buffer and render it

This requires integrating the Ghostty VT emulator's input processing, screen management, and renderer update mechanisms.

### Current Test Behavior

Currently, when you run tests:
- ✅ Test execution works (you'll see logs in logcat)
- ✅ Test timing and result tracking works
- ✅ UI updates show which test is running
- ❌ **Visual rendering does NOT work** (screen stays blank/unchanged)

The framework is ready - it just needs the VT emulator integration to be completed.

## Architecture

### Components

```
com.ghostty.android.testing/
├── TestCase.kt          # Test case data structures
├── TestSuite.kt         # Collection of test cases
├── TestRunner.kt        # Test execution engine
└── README.md            # This file
```

### How It Works

1. **TestCase**: Defines a test with ANSI sequences to inject
2. **TestSuite**: Organizes test cases by category (colors, attributes, cursor, etc.)
3. **TestRunner**: Executes tests by injecting ANSI sequences via `TerminalSession.writeInput()`
4. **MainActivity**: Provides UI to toggle test mode and run tests

## Using the Test Framework

### Accessing Test Mode

1. Launch the Ghostty Android app
2. Tap the "TEST" button in the top-right corner
3. You'll enter Test Mode with the visual regression test runner

### Running Tests

**Run All Tests:**
```kotlin
testRunner.runAllTests()
```

**Run Tests by Tag:**
```kotlin
testRunner.runTestsByTag("color")  // Run only color tests
testRunner.runTestsByTag("cursor") // Run only cursor tests
```

**Run Single Test:**
```kotlin
val test = TestSuite.getTestById("basic_colors_fg")
testRunner.runTest(test)
```

### Available Test Suites

**Color Tests** (`tag: "color"`)
- `basic_colors_fg` - 16 ANSI foreground colors
- `basic_colors_bg` - 16 ANSI background colors
- `256_colors` - 256 color palette
- `rgb_colors` - 24-bit RGB gradients

**Attribute Tests** (`tag: "attributes"`)
- `text_attributes` - Bold, italic, underline, etc.
- `combined_attributes` - Multiple attributes combined

**Cursor Tests** (`tag: "cursor"`)
- `cursor_position` - Absolute positioning
- `cursor_movement` - Relative movement

**Screen Tests** (`tag: "screen"`)
- `screen_clear` - Clear operations
- `line_operations` - Line editing

**Wrapping Tests** (`tag: "wrap"`)
- `line_wrap_basic` - Basic line wrapping behavior
- `line_wrap_word_boundary` - Word boundary wrapping
- `line_wrap_ansi_colors` - Color preservation across wrapped lines
- `scrollback` - Scrollback buffer test (30 lines)

**Character Set Tests** (`tag: "charset"`)
- `utf8_basic` - Latin, Greek, Cyrillic, CJK, Arabic
- `emoji` - Emoji rendering (faces, hearts, symbols)
- `box_drawing` - Unicode box drawing characters
- `special_chars` - Tab, bell, null, backspace handling
- `double_width` - CJK double-width characters
- `combining_chars` - Diacritical marks and combining characters

## Creating New Tests

### Example: Adding a Color Test

```kotlin
// In TestSuite.kt, add to getColorTests():
testCase("my_color_test", "Test description") {
    tags("color", "custom")

    // Clear screen and move cursor home
    ansi("\u001B[2J\u001B[H")

    // Write colored text
    ansi("\u001B[31mRed Text\u001B[0m\n")
    ansi("\u001B[32mGreen Text\u001B[0m\n")

    // Optional: Set terminal size
    terminalSize(80, 24)

    // Optional: Reference image for comparison
    referenceImage("assets/my_color_test.png")
}
```

### Test Case DSL

```kotlin
testCase("test_id", "Description") {
    // Add ANSI sequences
    ansi("\u001B[2J")          // Clear screen
    ansi("\u001B[31mRed\u001B[0m")  // Red text with reset

    // Set terminal dimensions
    terminalSize(cols = 80, rows = 24)

    // Add tags for categorization
    tags("color", "basic", "ansi")

    // Reference image (future use)
    referenceImage("test_id.png")
}
```

## ANSI Escape Sequences Reference

### Colors
```
Foreground: \u001B[30-37m (black-white)
Background: \u001B[40-47m (black-white)
Bright FG:  \u001B[90-97m
Bright BG:  \u001B[100-107m
256 color:  \u001B[38;5;<n>m (foreground)
            \u001B[48;5;<n>m (background)
RGB color:  \u001B[38;2;<r>;<g>;<b>m
```

### Text Attributes
```
Reset:        \u001B[0m
Bold:         \u001B[1m
Dim:          \u001B[2m
Italic:       \u001B[3m
Underline:    \u001B[4m
Reverse:      \u001B[7m
Strikethrough:\u001B[9m
```

### Cursor Movement
```
Home:         \u001B[H
Position:     \u001B[<row>;<col>H
Up n:         \u001B[<n>A
Down n:       \u001B[<n>B
Right n:      \u001B[<n>C
Left n:       \u001B[<n>D
```

### Screen Control
```
Clear screen: \u001B[2J
Clear line:   \u001B[2K
```

## Test Results

Test results include:
- **Status**: PASSED, FAILED, or SKIPPED
- **Duration**: Execution time in milliseconds
- **Message**: Success or error message
- **Screenshot**: Optional captured screenshot path

## Future Enhancements

### Short Term
1. **Screenshot Capture**: Automatically capture screenshots after each test
2. **Image Comparison**: Compare against reference images from Ghostty
3. **Test Reports**: Export test results as JSON/HTML

### Medium Term
4. **Port Ghostty Tests**: Convert `vttest.py` and `wraptest.py` to Kotlin test cases
5. **Automated Runs**: Run tests on app startup or via ADB intent
6. **CI Integration**: Run tests in GitHub Actions

### Long Term
7. **Visual Diff Tool**: Side-by-side comparison of test vs. reference
8. **Performance Metrics**: Track rendering performance per test
9. **PTY Integration**: Once PTY backend is ready, support command-based tests

## Comparison with Python Tests

| Feature | Python Tests | Integrated Tests |
|---------|--------------|------------------|
| Requires ADB | Yes | No |
| Requires Shell/PTY | Yes | No |
| Run Location | External | In-App |
| Command Execution | Yes (vttest, etc.) | No |
| ANSI Injection | Via commands | Direct |
| Visual Feedback | Screenshots only | Live + Screenshots |
| Setup Complexity | High | Low |

## Contributing

To add new test cases:

1. Add test case to appropriate suite in `TestSuite.kt`
2. Use meaningful test IDs and descriptions
3. Tag tests appropriately for categorization
4. Test your test case in the app before committing
5. Document any special ANSI sequences used

## References

- [ANSI Escape Codes](https://en.wikipedia.org/wiki/ANSI_escape_code)
- [Ghostty VT Tests](../../tests/visual/cases/)
- [Test Findings Report](../../tests/visual/FINDINGS.md)

## License

Same as Ghostty Android project.
