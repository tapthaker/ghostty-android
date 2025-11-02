#!/usr/bin/env python3
"""
Main CLI for running Ghostty Android visual regression tests.

Usage:
    python run_tests.py                    # Run all tests
    python run_tests.py --test vttest_1_1  # Run specific test
    python run_tests.py --list             # List all tests
    python run_tests.py --device SERIAL    # Use specific device
"""

import sys
import argparse
from pathlib import Path

# Add current directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from test_runner import TestRunner
from adb_controller import ADBController
from cases import get_all_tests


def main():
    parser = argparse.ArgumentParser(
        description="Ghostty Android Visual Regression Test Runner"
    )
    parser.add_argument(
        "--device", "-d",
        help="Android device serial number (optional, uses default if not specified)"
    )
    parser.add_argument(
        "--test", "-t",
        help="Run specific test by name (e.g., vttest_1_1)"
    )
    parser.add_argument(
        "--list", "-l",
        action="store_true",
        help="List all available tests"
    )
    parser.add_argument(
        "--output", "-o",
        type=Path,
        default=Path("test_output"),
        help="Output directory for screenshots and diffs (default: test_output)"
    )
    parser.add_argument(
        "--threshold",
        type=int,
        default=0,
        help="Pixel difference threshold for pass/fail (default: 0 = exact match)"
    )
    parser.add_argument(
        "--stop-on-failure",
        action="store_true",
        help="Stop test run on first failure"
    )
    parser.add_argument(
        "--no-cleanup",
        action="store_true",
        help="Don't stop app after tests"
    )

    args = parser.parse_args()

    # Get all tests
    all_tests = get_all_tests()

    # List tests if requested
    if args.list:
        print(f"\nAvailable tests ({len(all_tests)}):\n")
        for test in all_tests:
            ref_status = "✓" if test.reference_image and test.reference_image.exists() else "✗"
            print(f"  {ref_status} {test.name:20s} - {test.description}")
        print()
        return 0

    # Filter to specific test if requested
    if args.test:
        all_tests = [t for t in all_tests if t.name == args.test]
        if not all_tests:
            print(f"Error: Test '{args.test}' not found")
            return 1

    # Initialize ADB controller
    adb = ADBController(device_serial=args.device)

    # Check device connection
    print("Checking device connection...")
    if not adb.check_device():
        print("Error: No device connected or device not responding")
        print("Please connect an Android device and enable USB debugging")
        return 1

    device_info = args.device or "default"
    print(f"✓ Device connected: {device_info}\n")

    # Initialize test runner
    runner = TestRunner(
        adb=adb,
        output_dir=args.output,
        pixel_threshold=args.threshold
    )

    try:
        # Run tests
        summary = runner.run_tests(
            tests=all_tests,
            stop_on_failure=args.stop_on_failure
        )

        # Return exit code based on results
        return 0 if summary.failed == 0 and summary.errors == 0 else 1

    finally:
        # Cleanup unless disabled
        if not args.no_cleanup:
            runner.cleanup()


if __name__ == "__main__":
    sys.exit(main())
