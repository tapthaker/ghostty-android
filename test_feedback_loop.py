#!/usr/bin/env python3
"""
Automated Feedback Loop for Visual Testing

This script runs one test at a time, captures screenshots,
and allows for verification and iteration.

Usage:
    python test_feedback_loop.py [--test-id TEST_ID] [--start-from TEST_ID]
"""

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import List, Dict, Optional


# All available tests in order
ALL_TESTS = [
    "basic_colors_fg",
    "basic_colors_bg",
    "256_colors",
    "rgb_colors",
    "text_attributes",
    "combined_attributes",
    "cursor_position",
    "cursor_movement",
    "screen_clear",
    "line_operations",
    "line_wrap_basic",
    "line_wrap_word_boundary",
    "line_wrap_ansi_colors",
    "scrollback",
    "utf8_basic",
    "emoji",
    "box_drawing",
    "special_chars",
    "double_width",
    "combining_chars"
]


class TestFeedbackLoop:
    """Interactive feedback loop for visual regression testing."""

    def __init__(self, output_dir: str = "/tmp/feedback_tests"):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

        self.screenshots_dir = self.output_dir / "screenshots"
        self.screenshots_dir.mkdir(exist_ok=True)

        self.results_file = self.output_dir / "test_results.json"
        self.results = self.load_results()

    def load_results(self) -> Dict:
        """Load previous test results if they exist."""
        if self.results_file.exists():
            with open(self.results_file, 'r') as f:
                return json.load(f)
        return {}

    def save_results(self):
        """Save test results to file."""
        with open(self.results_file, 'w') as f:
            json.dump(self.results, f, indent=2)

    def check_device(self) -> bool:
        """Check if Android device is connected."""
        try:
            result = subprocess.run(
                ["adb", "devices"],
                capture_output=True,
                text=True,
                check=True
            )
            lines = result.stdout.strip().split('\n')
            devices = [line for line in lines[1:] if line.strip()]

            if not devices:
                print("❌ No Android devices connected")
                return False

            print(f"✓ Found {len(devices)} device(s) connected")
            return True
        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            print(f"❌ Error checking device: {e}")
            return False

    def launch_test(self, test_id: str) -> bool:
        """Launch app with specific test."""
        print(f"\n{'='*60}")
        print(f"  LAUNCHING TEST: {test_id}")
        print(f"{'='*60}\n")

        # First, clear logcat
        subprocess.run(["adb", "logcat", "-c"], capture_output=True)

        # Launch app with auto-start and specific test
        cmd = [
            "adb", "shell", "am", "start",
            "-n", "com.ghostty.android/.MainActivity",
            "--ez", "AUTO_START_TESTS", "true",
            "--es", "TEST_ID", test_id
        ]

        try:
            subprocess.run(cmd, capture_output=True, text=True, check=True)
            print("✓ App launched with test")
            return True
        except subprocess.CalledProcessError as e:
            print(f"❌ Failed to launch app: {e}")
            return False

    def monitor_test_completion(self, test_id: str, timeout: int = 30) -> bool:
        """Monitor logcat for test completion signal."""
        print(f"⏱  Monitoring test execution (timeout: {timeout}s)...")

        # Start logcat
        logcat_process = subprocess.Popen(
            ["adb", "logcat", "-v", "brief", "TestRunner:I", "*:S"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1
        )

        start_time = time.time()
        test_started = False
        test_ready = False
        test_complete = False

        try:
            while (time.time() - start_time) < timeout:
                line = logcat_process.stdout.readline()
                if not line:
                    if logcat_process.poll() is not None:
                        break
                    continue

                if f"TEST_START:{test_id}" in line:
                    test_started = True
                    print("  ▶  Test started")

                if f"TEST_READY:{test_id}" in line:
                    test_ready = True
                    print("  📸 Test ready for screenshot")

                if f"TEST_COMPLETE:{test_id}" in line:
                    test_complete = True
                    print("  ✓  Test completed")
                    break

            return test_complete
        finally:
            logcat_process.terminate()
            logcat_process.wait()

    def capture_screenshot(self, test_id: str) -> Optional[Path]:
        """Capture screenshot from device."""
        print("\n📸 Capturing screenshot...")

        screenshot_path = self.screenshots_dir / f"{test_id}.png"

        try:
            # Capture screenshot directly
            result = subprocess.run(
                ["adb", "exec-out", "screencap", "-p"],
                capture_output=True,
                check=True,
                timeout=5
            )

            # Write to file
            with open(screenshot_path, 'wb') as f:
                f.write(result.stdout)

            print(f"✓ Screenshot saved: {screenshot_path}")
            return screenshot_path
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
            print(f"❌ Failed to capture screenshot: {e}")
            return None

    def display_screenshot(self, screenshot_path: Path):
        """Display screenshot for verification."""
        print(f"\n🖼  Screenshot: file://{screenshot_path.absolute()}")

        # Try to open with default image viewer
        try:
            subprocess.run(["xdg-open", str(screenshot_path)], check=False)
        except:
            pass

    def verify_test(self, test_id: str, screenshot_path: Path) -> bool:
        """Interactive verification of test result."""
        print(f"\n{'='*60}")
        print(f"  VERIFY TEST: {test_id}")
        print(f"{'='*60}")
        print(f"\nScreenshot: {screenshot_path}")
        print("\nPlease verify the screenshot:")
        print("  - Check colors are correct")
        print("  - Check text is rendered properly")
        print("  - Check layout matches expectations")

        while True:
            response = input("\nDoes the test PASS? (y/n/skip/quit): ").lower().strip()

            if response == 'y' or response == 'yes':
                return True
            elif response == 'n' or response == 'no':
                return False
            elif response == 's' or response == 'skip':
                return None  # Skip this test
            elif response == 'q' or response == 'quit':
                sys.exit(0)
            else:
                print("Invalid response. Please enter y, n, skip, or quit")

    def run_single_test(self, test_id: str) -> Optional[bool]:
        """Run a single test through the feedback loop."""
        print(f"\n\n{'#'*60}")
        print(f"#  TEST: {test_id}")
        print(f"{'#'*60}\n")

        # Check if already passed
        if test_id in self.results and self.results[test_id].get("status") == "PASSED":
            print(f"ℹ  Test {test_id} already PASSED")
            response = input("Run again? (y/n): ").lower().strip()
            if response != 'y' and response != 'yes':
                return True

        # Launch test
        if not self.launch_test(test_id):
            return False

        # Wait for app to start
        time.sleep(3)

        # Monitor test execution
        if not self.monitor_test_completion(test_id):
            print("⚠️  Test did not complete within timeout")
            return False

        # Wait a bit more for rendering to settle
        time.sleep(1)

        # Capture screenshot
        screenshot_path = self.capture_screenshot(test_id)
        if not screenshot_path:
            return False

        # Display screenshot
        self.display_screenshot(screenshot_path)

        # Verify
        result = self.verify_test(test_id, screenshot_path)

        if result is None:  # Skipped
            print(f"\n⏭  Test {test_id} skipped")
            self.results[test_id] = {
                "status": "SKIPPED",
                "screenshot": str(screenshot_path),
                "timestamp": time.strftime("%Y-%m-%d %H:%M:%S")
            }
            self.save_results()
            return None

        if result:
            print(f"\n✅ Test {test_id} PASSED")
            self.results[test_id] = {
                "status": "PASSED",
                "screenshot": str(screenshot_path),
                "timestamp": time.strftime("%Y-%m-%d %H:%M:%S")
            }
        else:
            print(f"\n❌ Test {test_id} FAILED")
            self.results[test_id] = {
                "status": "FAILED",
                "screenshot": str(screenshot_path),
                "timestamp": time.strftime("%Y-%m-%d %H:%M:%S")
            }
            print("\n📝 Notes for fixing:")
            notes = input("Enter notes about what needs to be fixed: ")
            self.results[test_id]["notes"] = notes

        self.save_results()
        return result

    def run_loop(self, test_ids: List[str]):
        """Run the feedback loop for multiple tests."""
        print("\n" + "="*60)
        print("  AUTOMATED TEST FEEDBACK LOOP")
        print("="*60)
        print(f"\nRunning {len(test_ids)} tests")
        print(f"Output directory: {self.output_dir}")

        if not self.check_device():
            return

        passed = 0
        failed = 0
        skipped = 0

        for i, test_id in enumerate(test_ids, 1):
            print(f"\n\n{'='*60}")
            print(f"  Progress: {i}/{len(test_ids)}")
            print(f"  Passed: {passed} | Failed: {failed} | Skipped: {skipped}")
            print(f"{'='*60}")

            result = self.run_single_test(test_id)

            if result is True:
                passed += 1
            elif result is False:
                failed += 1
                print("\n⚠️  Test failed. Fix the issues and re-run this test.")
                response = input("Continue to next test? (y/n): ").lower().strip()
                if response != 'y' and response != 'yes':
                    break
            else:  # Skipped
                skipped += 1

        # Final summary
        print(f"\n\n{'='*60}")
        print("  FINAL RESULTS")
        print(f"{'='*60}")
        print(f"\nTotal: {len(test_ids)}")
        print(f"Passed: {passed}")
        print(f"Failed: {failed}")
        print(f"Skipped: {skipped}")
        print(f"\nResults saved to: {self.results_file}")
        print(f"Screenshots saved to: {self.screenshots_dir}")


def main():
    parser = argparse.ArgumentParser(
        description="Automated feedback loop for visual testing"
    )
    parser.add_argument(
        "--test-id",
        help="Run a specific test by ID"
    )
    parser.add_argument(
        "--start-from",
        help="Start from a specific test ID (inclusive)"
    )
    parser.add_argument(
        "--output", "-o",
        default="/tmp/feedback_tests",
        help="Output directory for results (default: /tmp/feedback_tests)"
    )

    args = parser.parse_args()

    # Determine which tests to run
    if args.test_id:
        test_ids = [args.test_id]
    elif args.start_from:
        try:
            start_index = ALL_TESTS.index(args.start_from)
            test_ids = ALL_TESTS[start_index:]
        except ValueError:
            print(f"Error: Test ID '{args.start_from}' not found in test list")
            sys.exit(1)
    else:
        test_ids = ALL_TESTS

    # Run the feedback loop
    loop = TestFeedbackLoop(args.output)
    loop.run_loop(test_ids)


if __name__ == "__main__":
    main()
