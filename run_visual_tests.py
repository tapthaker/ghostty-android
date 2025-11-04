#!/usr/bin/env python3
"""
Visual Test Orchestrator for Ghostty Android

This script coordinates with the Android app to run visual regression tests:
1. Launches the test suite in the app
2. Monitors for screenshot signals from the app
3. Captures screenshots via ADB when signaled
4. Collects all screenshots for analysis
5. Generates a test report

Usage:
    python run_visual_tests.py --output /path/to/output/dir [--tag color] [--test test_id]
"""

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Optional


class VisualTestRunner:
    """Orchestrates visual regression tests for Ghostty Android."""

    def __init__(self, output_dir: str, package: str = "com.ghostty.android"):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

        self.package = package
        self.device_screenshot_dir = f"/sdcard/Android/data/{package}/files/test_screenshots"
        self.local_screenshot_dir = self.output_dir / "screenshots"
        self.local_screenshot_dir.mkdir(parents=True, exist_ok=True)

        self.results: List[Dict] = []

    def check_adb_connection(self) -> bool:
        """Check if an Android device is connected via ADB."""
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
                print("ERROR: No Android devices connected via ADB")
                return False

            print(f"Found {len(devices)} device(s) connected")
            return True
        except subprocess.CalledProcessError as e:
            print(f"ERROR: Failed to run adb command: {e}")
            return False
        except FileNotFoundError:
            print("ERROR: adb command not found. Please install Android SDK Platform-Tools")
            return False

    def launch_tests(self, tag: Optional[str] = None, test_id: Optional[str] = None) -> bool:
        """
        Launch the test suite in the Android app via ADB.

        Args:
            tag: Optional tag to filter tests (e.g., "color", "cursor")
            test_id: Optional specific test ID to run
        """
        print("\n=== Launching Tests ===")

        # Build the intent extras
        extras = []
        if tag:
            extras.extend(["--es", "tag", tag])
        if test_id:
            extras.extend(["--es", "test_id", test_id])
        extras.append("--ez")
        extras.append("run_tests")
        extras.append("true")

        # Launch the app with test mode enabled
        cmd = [
            "adb", "shell", "am", "start",
            "-n", f"{self.package}/.MainActivity",
            *extras
        ]

        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            print("Tests launched successfully")
            print(f"Command: {' '.join(cmd)}")
            return True
        except subprocess.CalledProcessError as e:
            print(f"ERROR: Failed to launch tests: {e}")
            print(f"Output: {e.output}")
            return False

    def monitor_and_capture(self, timeout: int = 300) -> None:
        """
        Monitor for screenshot signals and capture screenshots.

        Args:
            timeout: Maximum time to wait for signals (seconds)
        """
        print("\n=== Monitoring for Screenshot Signals ===")
        print(f"Watching device directory: {self.device_screenshot_dir}")

        start_time = time.time()
        last_activity = time.time()
        captured_tests = set()

        while (time.time() - start_time) < timeout:
            # Check for signal files
            try:
                result = subprocess.run(
                    ["adb", "shell", "ls", self.device_screenshot_dir],
                    capture_output=True,
                    text=True,
                    timeout=5
                )

                if result.returncode == 0:
                    files = result.stdout.strip().split('\n')
                    signal_files = [f for f in files if f.endswith('.signal')]

                    for signal_file in signal_files:
                        test_id = signal_file.replace('.signal', '')

                        if test_id not in captured_tests:
                            print(f"\n📸 Capturing screenshot for: {test_id}")

                            if self.capture_screenshot(test_id):
                                captured_tests.add(test_id)
                                last_activity = time.time()

                                # Remove the signal file to acknowledge
                                subprocess.run(
                                    ["adb", "shell", "rm",
                                     f"{self.device_screenshot_dir}/{signal_file}"],
                                    capture_output=True
                                )

                                self.results.append({
                                    "test_id": test_id,
                                    "status": "captured",
                                    "timestamp": datetime.now().isoformat(),
                                    "screenshot": f"screenshots/{test_id}.png"
                                })

                # Check if we've been idle for too long
                if captured_tests and (time.time() - last_activity) > 10:
                    print(f"\n✅ No new signals for 10 seconds, finishing up")
                    break

            except subprocess.TimeoutExpired:
                print(".", end="", flush=True)

            time.sleep(0.5)

        print(f"\n\n=== Capture Summary ===")
        print(f"Captured {len(captured_tests)} screenshots")
        print(f"Tests: {', '.join(sorted(captured_tests))}")

    def capture_screenshot(self, test_id: str) -> bool:
        """
        Capture a screenshot via ADB screencap.

        Args:
            test_id: The test identifier for naming the screenshot

        Returns:
            True if screenshot was captured successfully
        """
        device_path = f"/sdcard/ghostty_test_{test_id}.png"
        local_path = self.local_screenshot_dir / f"{test_id}.png"

        try:
            # Capture screenshot on device
            subprocess.run(
                ["adb", "shell", "screencap", "-p", device_path],
                capture_output=True,
                check=True,
                timeout=5
            )

            # Pull screenshot to local machine
            subprocess.run(
                ["adb", "pull", device_path, str(local_path)],
                capture_output=True,
                check=True,
                timeout=10
            )

            # Clean up device screenshot
            subprocess.run(
                ["adb", "shell", "rm", device_path],
                capture_output=True
            )

            print(f"  ✓ Saved to: {local_path}")
            return True

        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
            print(f"  ✗ Failed to capture screenshot: {e}")
            return False

    def generate_report(self) -> None:
        """Generate a JSON report of test results."""
        report_path = self.output_dir / "test_report.json"

        report = {
            "timestamp": datetime.now().isoformat(),
            "total_tests": len(self.results),
            "results": self.results
        }

        with open(report_path, 'w') as f:
            json.dump(report, f, indent=2)

        print(f"\n=== Test Report ===")
        print(f"Report saved to: {report_path}")
        print(f"Screenshots saved to: {self.local_screenshot_dir}")
        print(f"\nTotal tests: {len(self.results)}")

        # Generate HTML index
        self.generate_html_index()

    def generate_html_index(self) -> None:
        """Generate an HTML index page to view all screenshots."""
        html_path = self.output_dir / "index.html"

        html_content = """<!DOCTYPE html>
<html>
<head>
    <title>Ghostty Visual Test Results</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 40px;
            background: #f5f5f5;
        }
        h1 {
            color: #333;
        }
        .test-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(400px, 1fr));
            gap: 20px;
            margin-top: 30px;
        }
        .test-card {
            background: white;
            border-radius: 8px;
            padding: 15px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .test-card h3 {
            margin-top: 0;
            color: #444;
            font-size: 16px;
            font-family: monospace;
        }
        .test-card img {
            width: 100%;
            border: 1px solid #ddd;
            border-radius: 4px;
        }
        .test-card .timestamp {
            color: #888;
            font-size: 12px;
            margin-top: 10px;
        }
    </style>
</head>
<body>
    <h1>Ghostty Visual Test Results</h1>
    <p>Generated: {timestamp}</p>
    <p>Total tests: {total}</p>

    <div class="test-grid">
"""

        for result in sorted(self.results, key=lambda x: x['test_id']):
            html_content += f"""
        <div class="test-card">
            <h3>{result['test_id']}</h3>
            <img src="{result['screenshot']}" alt="{result['test_id']}">
            <div class="timestamp">{result['timestamp']}</div>
        </div>
"""

        html_content += """
    </div>
</body>
</html>
"""

        with open(html_path, 'w') as f:
            f.write(html_content.format(
                timestamp=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                total=len(self.results)
            ))

        print(f"HTML index saved to: {html_path}")
        print(f"\nView results: file://{html_path.absolute()}")


def main():
    parser = argparse.ArgumentParser(
        description="Run visual regression tests for Ghostty Android"
    )
    parser.add_argument(
        "--output", "-o",
        required=True,
        help="Output directory for screenshots and reports"
    )
    parser.add_argument(
        "--tag", "-t",
        help="Run only tests with this tag (e.g., 'color', 'cursor')"
    )
    parser.add_argument(
        "--test",
        help="Run a specific test by ID"
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=300,
        help="Maximum time to wait for tests (seconds, default: 300)"
    )
    parser.add_argument(
        "--package",
        default="com.ghostty.android",
        help="Android package name (default: com.ghostty.android)"
    )

    args = parser.parse_args()

    # Create test runner
    runner = VisualTestRunner(args.output, args.package)

    # Check ADB connection
    if not runner.check_adb_connection():
        sys.exit(1)

    # Launch tests
    if not runner.launch_tests(tag=args.tag, test_id=args.test):
        sys.exit(1)

    # Give the app time to start
    print("\nWaiting for app to initialize...")
    time.sleep(3)

    # Monitor and capture screenshots
    runner.monitor_and_capture(timeout=args.timeout)

    # Generate report
    runner.generate_report()

    print("\n✅ Visual test run completed!")


if __name__ == "__main__":
    main()
