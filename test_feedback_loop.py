#!/usr/bin/env python3
"""
Test Feedback Loop with Manual Navigation

This script launches tests with manual next/prev navigation controls.

Usage:
    python test_feedback_loop.py [--test-id TEST_ID]
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
    "cursor_visibility",
    "cursor_styles",
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
    """Automated screenshot capture for visual testing."""

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
        """Launch app with specific test in manual navigation mode."""
        print(f"\n{'='*60}")
        print(f"  LAUNCHING TEST: {test_id}")
        print(f"{'='*60}\n")

        # First, force-stop any existing instance
        try:
            subprocess.run(
                ["adb", "shell", "am", "force-stop", "com.ghostty.android"],
                capture_output=True,
                check=True
            )
            print("✓ Stopped existing app instance")
            time.sleep(1)  # Give it a moment to fully stop
        except subprocess.CalledProcessError as e:
            print(f"⚠️  Warning: Failed to stop app: {e}")

        # Clear logcat
        subprocess.run(["adb", "logcat", "-c"], capture_output=True)

        # Launch app with specific test ID
        cmd = [
            "adb", "shell", "am", "start",
            "-n", "com.ghostty.android/.MainActivity",
            "--ez", "AUTO_START_TESTS", "true",
            "--es", "TEST_ID", test_id
        ]

        try:
            subprocess.run(cmd, capture_output=True, text=True, check=True)
            print("✓ App launched with manual navigation")
            return True
        except subprocess.CalledProcessError as e:
            print(f"❌ Failed to launch app: {e}")
            return False


    def run_tests(self, test_id: str = "all"):
        """Run tests with manual navigation."""
        print("\n" + "="*60)
        print("  TEST NAVIGATION MODE")
        print("="*60)
        print(f"\nOutput directory: {self.output_dir}")
        print("\nInstructions:")
        print("  • Use NEXT/PREVIOUS buttons to navigate between tests")
        print("  • Screenshot can be captured anytime with 'adb exec-out screencap -p > test.png'")
        print("  • App will remain open for manual interaction")

        if not self.check_device():
            return

        # Launch app with specified test ID
        if not self.launch_test(test_id):
            print("❌ Failed to launch app")
            return

        print("\n✅ App launched with manual navigation")
        print("📱 Navigate tests using the on-screen buttons")
        print("⌨️  Press Enter to stop...")

        # Wait for user to press Enter
        try:
            input()
        except (KeyboardInterrupt, EOFError):
            pass

        # Stop the app when done
        try:
            subprocess.run(
                ["adb", "shell", "am", "force-stop", "com.ghostty.android"],
                capture_output=True,
                check=True
            )
            print("✓ Stopped app")
        except subprocess.CalledProcessError as e:
            print(f"⚠️  Warning: Failed to stop app: {e}")


def main():
    parser = argparse.ArgumentParser(
        description="Test feedback loop with manual navigation"
    )
    parser.add_argument(
        "--test-id",
        default="all",
        help="Test ID to start at (default: all) - Always loads all tests for navigation"
    )
    parser.add_argument(
        "--output", "-o",
        default="/tmp/feedback_tests",
        help="Output directory for results (default: /tmp/feedback_tests)"
    )

    args = parser.parse_args()

    # Create feedback loop instance
    loop = TestFeedbackLoop(args.output)

    # Run tests with manual navigation
    loop.run_tests(args.test_id)


if __name__ == "__main__":
    main()
