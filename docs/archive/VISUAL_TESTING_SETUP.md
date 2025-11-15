# Visual Testing with Screenshot Capture

This document describes the automated screenshot capture system for Ghostty Android's visual regression tests.

## Overview

The visual testing system consists of three main components:
1. **Android App** - Runs tests and signals when screenshots should be taken
2. **Python Orchestrator** (`run_visual_tests.py`) - Monitors signals and captures screenshots via ADB
3. **Comparison Tool** (`compare_screenshots.py`) - Compares screenshots across test runs

## How It Works

```
┌─────────────────┐
│  Android App    │
│  ┌───────────┐  │
│  │TestRunner │──┼──> Creates signal file: test_screenshots/test_id.signal
│  └───────────┘  │
└─────────────────┘
         │
         v
┌─────────────────┐
│  Host Machine   │
│  ┌───────────┐  │
│  │run_visual_│  │
│  │tests.py   │  │◄─── Monitors for signal files
│  └───────────┘  │
│        │        │
│        v        │
│   [Captures     │
│   screenshot    │
│   via ADB]      │
│        │        │
│        v        │
│   [Removes      │
│   signal file]  │◄─── App waits for removal
└─────────────────┘
         │
         v
    [Test continues]
```

### Signal File Protocol

1. When a test is ready for screenshot capture, the app creates a signal file:
   ```
   /sdcard/Android/data/com.ghostty.android/files/test_screenshots/<test_id>.signal
   ```

2. The Python orchestrator detects this file and captures a screenshot via `adb screencap`

3. The orchestrator removes the signal file to acknowledge completion

4. The app detects the signal file removal and continues to the next test

## Setup

### Prerequisites

- Android device or emulator connected via ADB
- Python 3.6+
- Android SDK Platform Tools (for `adb`)

### Optional: Install Pillow for Image Comparison

```bash
pip install Pillow numpy
```

## Usage

### Running Tests with Screenshot Capture

#### Run All Tests

```bash
python run_visual_tests.py --output /tmp/ghostty_tests
```

#### Run Tests by Tag

```bash
# Run only color tests
python run_visual_tests.py --output /tmp/ghostty_tests --tag color

# Run only cursor tests
python run_visual_tests.py --output /tmp/ghostty_tests --tag cursor
```

#### Run a Specific Test

```bash
python run_visual_tests.py --output /tmp/ghostty_tests --test basic_colors_fg
```

#### Specify Timeout

```bash
python run_visual_tests.py --output /tmp/ghostty_tests --timeout 600
```

### Script Options

```
--output, -o  : Output directory for screenshots and reports (required)
--tag, -t     : Run only tests with this tag (optional)
--test        : Run a specific test by ID (optional)
--timeout     : Maximum time to wait for tests in seconds (default: 300)
--package     : Android package name (default: com.ghostty.android)
```

### Output Structure

After running tests, the output directory contains:

```
output_dir/
├── screenshots/
│   ├── basic_colors_fg.png
│   ├── basic_colors_bg.png
│   └── ...
├── test_report.json
└── index.html
```

- **screenshots/** - PNG images captured for each test
- **test_report.json** - Structured test results with metadata
- **index.html** - Visual browser-friendly report

### Viewing Results

Open the generated HTML report in a browser:

```bash
# Linux
xdg-open /tmp/ghostty_tests/index.html

# macOS
open /tmp/ghostty_tests/index.html
```

## Comparing Screenshots

To compare screenshots between two test runs:

```bash
python compare_screenshots.py \
  --baseline /tmp/baseline_run/screenshots \
  --current /tmp/current_run/screenshots \
  --output /tmp/comparison
```

### Comparison Output

```
comparison/
├── diffs/
│   ├── test_id_diff.png       # Side-by-side visualization
│   └── ...
├── comparison_report.json
└── comparison_report.html
```

### Understanding Diff Images

Diff images show three panels:
1. **Baseline** - Reference screenshot (left)
2. **Current** - New screenshot (middle)
3. **Difference (10x)** - Amplified differences (right)

### Exit Codes

The comparison script exits with:
- **0** - All screenshots match
- **1** - Differences or missing screenshots found

This makes it suitable for CI/CD pipelines.

## CI/CD Integration

### Example GitHub Actions Workflow

```yaml
name: Visual Regression Tests

on: [push, pull_request]

jobs:
  visual-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up Android Emulator
        uses: reactivecircus/android-emulator-runner@v2
        with:
          api-level: 31
          script: |
            # Build and install app
            make android

            # Run visual tests
            python run_visual_tests.py --output /tmp/tests

            # Compare with baseline
            python compare_screenshots.py \
              --baseline ./baseline_screenshots \
              --current /tmp/tests/screenshots \
              --output /tmp/comparison

      - name: Upload Results
        if: failure()
        uses: actions/upload-artifact@v3
        with:
          name: visual-test-results
          path: /tmp/comparison/
```

## Available Test Suites

The following test suites are available (see TestSuite.kt for full list):

| Tag | Tests | Description |
|-----|-------|-------------|
| `color` | 4 | ANSI colors (16, 256, RGB) |
| `attributes` | 2 | Text styling (bold, italic, etc.) |
| `cursor` | 2 | Cursor positioning and movement |
| `screen` | 2 | Screen clearing and line operations |
| `wrap` | 4 | Line wrapping and reflow |
| `charset` | 6 | Character sets, emoji, CJK |

## Troubleshooting

### No Screenshots Captured

1. Check if device is connected:
   ```bash
   adb devices
   ```

2. Check logcat for TestRunner logs:
   ```bash
   adb logcat TestRunner:I *:S
   ```

3. Verify signal file directory exists:
   ```bash
   adb shell ls /sdcard/Android/data/com.ghostty.android/files/test_screenshots
   ```

### Signal Files Not Being Removed

If signal files accumulate without being removed:

1. Check if Python script is running
2. Verify ADB permissions
3. Manually clean up:
   ```bash
   adb shell rm /sdcard/Android/data/com.ghostty.android/files/test_screenshots/*.signal
   ```

### Screenshots Are Blank

The terminal rendering may not be connected to the VT emulator yet. See the testing README for details on the current architectural limitations.

### Permission Denied Errors

Grant storage permissions to the app:

```bash
adb shell pm grant com.ghostty.android android.permission.WRITE_EXTERNAL_STORAGE
adb shell pm grant com.ghostty.android android.permission.READ_EXTERNAL_STORAGE
```

## Development Tips

### Adding New Tests

1. Add test case to `TestSuite.kt`:
   ```kotlin
   testCase("my_new_test", "Description") {
       tags("category")
       ansi("\u001B[2J\u001B[H")  // Clear screen
       ansi("Test content")
   }
   ```

2. Run the test:
   ```bash
   python run_visual_tests.py --test my_new_test --output /tmp/test
   ```

3. Review the screenshot in `/tmp/test/screenshots/my_new_test.png`

### Debugging Test Execution

Monitor TestRunner logs during test execution:

```bash
adb logcat TestRunner:D *:S
```

### Manual Screenshot Capture

To manually trigger screenshot capture without the orchestrator:

```bash
# Take screenshot
adb exec-out screencap -p > screenshot.png

# Or save to device first
adb shell screencap -p /sdcard/screenshot.png
adb pull /sdcard/screenshot.png
```

## Future Enhancements

Planned improvements:

1. **Parallel Test Execution** - Run multiple tests simultaneously
2. **Baseline Management** - Store and version baseline screenshots
3. **Perceptual Diff** - Use structural similarity index (SSIM) for comparison
4. **Test Recording** - Record video of test execution
5. **Performance Metrics** - Track frame times and rendering performance
6. **Cloud Storage** - Upload results to S3/GCS for historical analysis

## See Also

- [Testing Framework README](android/app/src/main/java/com/ghostty/android/testing/README.md) - In-app testing documentation
- [TestSuite.kt](android/app/src/main/java/com/ghostty/android/testing/TestSuite.kt) - Available test cases
- [TestRunner.kt](android/app/src/main/java/com/ghostty/android/testing/TestRunner.kt) - Test execution engine

## Contributing

When adding screenshot-based tests:

1. Ensure tests are deterministic (same input → same output)
2. Avoid time-dependent or animated content
3. Use standard terminal sizes (80x24 is recommended)
4. Tag tests appropriately for easy filtering
5. Document expected behavior in test descriptions

## License

Same as Ghostty Android project.
