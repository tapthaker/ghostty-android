# Ghostty Android Visual Regression Tests

This directory contains visual regression tests for the Ghostty Android terminal renderer, converted from the Ghostty OSS test suite.

## Overview

The test framework:
- **Converts** Ghostty OSS shell-based tests to Python
- **Runs** tests on Android devices via ADB
- **Captures** screenshots of rendered output
- **Compares** against reference images from Ghostty OSS
- **Reports** pixel-level differences

## Test Cases

All tests from `libghostty-vt/test/cases/` have been converted:

### VT Test Suite (`vttest`)
- `vttest_launch` - Menu display
- `vttest_1_1` - Cursor movements
- `vttest_1_2` - Screen features
- `vttest_1_3` - Character sets
- `vttest_1_4` - Double-sized characters
- `vttest_1_5` - Keyboard test
- `vttest_1_6` - Terminal reports

### Line Wrapping (`wraptest`)
- `wraptest` - Line wrapping matrix

## Prerequisites

### System Requirements
- Python 3.8+
- Android Debug Bridge (ADB)
- ImageMagick (for image comparison) OR PIL/Pillow

### Install Dependencies

```bash
# Install Python dependencies
cd tests
pip install -r requirements.txt

# Install ImageMagick (Ubuntu/Debian)
sudo apt-get install imagemagick

# OR use PIL/Pillow (already in requirements.txt)
```

### Android Setup
1. Connect Android device via USB
2. Enable USB debugging in Developer Options
3. Accept USB debugging authorization on device
4. Verify connection: `adb devices`

## Running Tests

### Run All Tests
```bash
cd tests/visual
python run_tests.py
```

### Run Specific Test
```bash
python run_tests.py --test vttest_1_1
```

### List Available Tests
```bash
python run_tests.py --list
```

### Use Specific Device
```bash
python run_tests.py --device <serial>
```

### Adjust Pixel Threshold
```bash
# Allow up to 100 pixels difference
python run_tests.py --threshold 100
```

### Stop on First Failure
```bash
python run_tests.py --stop-on-failure
```

## Output

Test output is saved to `test_output/` (configurable with `--output`):
```
test_output/
├── screenshots/          # Actual screenshots from device
│   ├── vttest_1_1.actual.png
│   └── ...
└── diffs/               # Visual diffs (only for failures)
    ├── vttest_1_1.diff.png
    └── ...
```

## Test Results

Example output:
```
======================================================================
Running 8 visual regression tests
Device: default
Output: test_output
Threshold: 0 pixels
======================================================================

[1/8]   Running: vttest_launch ... ✓ PASS (2.45s)
[2/8]   Running: vttest_1_1 ... ✓ PASS (3.12s)
[3/8]   Running: vttest_1_2 ... ✗ FAIL (diff: 245 pixels, 3.05s)
...

======================================================================
Test Summary
======================================================================
Total:    8
Passed:   7 ✓
Failed:   1 ✗
Errors:   0 ⚠
Success:  87.5%
Duration: 24.32s
======================================================================
```

## Framework Architecture

```
tests/visual/
├── __init__.py              # Package init
├── test_case.py             # TestCase and Action definitions
├── adb_controller.py        # ADB device interaction
├── image_compare.py         # Image comparison (ImageMagick + PIL)
├── test_runner.py           # Test execution engine
├── run_tests.py             # Main CLI entry point
└── cases/                   # Test case definitions
    ├── __init__.py          # Test discovery
    ├── vttest.py            # VT test suite cases
    └── wraptest.py          # Line wrapping test
```

## Adding New Tests

To add a new test case:

1. Create test function in `cases/<module>.py`:
```python
def test_new_feature() -> TestCase:
    test = TestCase(
        name="new_feature",
        description="Test description"
    )
    test.add_type("command")
    test.add_key("Return")
    test.add_sleep(1.0)
    test.reference_image = REFERENCE_DIR / "new_feature.sh.ghostty.png"
    return test
```

2. Add to module's `get_tests()` function
3. Run to generate initial screenshot (will pass without reference)
4. Manually verify screenshot is correct
5. Copy to reference image location

## CI/CD Integration

The test runner returns exit code 0 on success, 1 on failure, making it suitable for CI:

```bash
#!/bin/bash
# CI script example
python tests/visual/run_tests.py --threshold 0 --stop-on-failure
exit $?
```

## Troubleshooting

### "No device connected"
- Check `adb devices` shows your device
- Verify USB debugging is enabled
- Check USB connection/cable

### "Failed to launch app"
- Ensure app is installed: `make android`
- Check package name matches: `com.ghostty.android`

### "ImageMagick not found"
- Install ImageMagick: `sudo apt-get install imagemagick`
- OR framework will fall back to PIL/Pillow

### Tests fail with pixel differences
- Fonts may differ between devices
- Screen density may affect rendering
- Use `--threshold` to allow minor differences
- Check diff images in `test_output/diffs/`

## Future Enhancements

- [ ] Direct VT sequence injection (bypass keyboard simulation)
- [ ] Terminal state verification via JNI hooks
- [ ] Parallel test execution
- [ ] HTML test report generation
- [ ] Integration with Android Instrumentation tests
- [ ] Custom test programs (beyond vttest/wraptest)
