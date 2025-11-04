#!/usr/bin/env python3
"""
Simple Visual Test Runner for Ghostty Android

This script monitors logcat for test readiness signals and captures screenshots.

Usage:
    python run_visual_tests_simple.py --output /path/to/output/dir [--tag color]
"""

import argparse
import json
import os
import subprocess
import sys
import time
import re
from datetime import datetime
from pathlib import Path
from typing import List, Dict


class SimpleTestRunner:
    """Simple test runner that monitors logcat and captures screenshots."""

    def __init__(self, output_dir: str, package: str = "com.ghostty.android"):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

        self.package = package
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
        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            print(f"ERROR: {e}")
            return False

    def launch_app_in_test_mode(self, test_tag: str = None) -> bool:
        """Launch the app in test mode with auto-start."""
        print("\n=== Launching App in Test Mode ===")

        # Launch the app with intent extras to auto-start tests
        cmd = [
            "adb", "shell", "am", "start",
            "-n", f"{self.package}/.MainActivity",
            "--ez", "AUTO_START_TESTS", "true"
        ]

        # Add test tag if specified
        if test_tag:
            cmd.extend(["--es", "TEST_TAG", test_tag])
            print(f"Auto-starting tests with tag: {test_tag}")
        else:
            print("Auto-starting all tests")

        try:
            subprocess.run(cmd, capture_output=True, text=True, check=True)
            print("App launched successfully with auto-start enabled")
            return True
        except subprocess.CalledProcessError as e:
            print(f"ERROR: Failed to launch app: {e}")
            return False

    def monitor_and_capture(self, timeout: int = 300) -> None:
        """Monitor logcat for TEST_READY signals and capture screenshots."""
        print("\n=== Monitoring for Tests ===")
        print("Watching logcat for TEST_READY signals...")

        # Start logcat process
        logcat_cmd = [
            "adb", "logcat", "-v", "brief",
            "TestRunner:I", "*:S"
        ]

        start_time = time.time()
        last_activity = time.time()

        try:
            process = subprocess.Popen(
                logcat_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1
            )

            print("\nWaiting for tests to start...")
            print("(Start the tests in the app now)\n")

            test_pattern = re.compile(r'TEST_(START|READY|COMPLETE):(\S+)')

            while (time.time() - start_time) < timeout:
                line = process.stdout.readline()
                if not line:
                    if process.poll() is not None:
                        break
                    continue

                # Look for test signals
                match = test_pattern.search(line)
                if match:
                    signal_type, test_id = match.groups()

                    if signal_type == "START":
                        print(f"▶ Test started: {test_id}")
                        last_activity = time.time()

                    elif signal_type == "READY":
                        print(f"  📸 Capturing screenshot: {test_id}")
                        if self.capture_screenshot(test_id):
                            self.results.append({
                                "test_id": test_id,
                                "status": "captured",
                                "timestamp": datetime.now().isoformat(),
                                "screenshot": f"screenshots/{test_id}.png"
                            })
                        last_activity = time.time()

                    elif signal_type == "COMPLETE":
                        print(f"  ✓ Test completed: {test_id}")
                        last_activity = time.time()

                # Check if we've been idle too long
                if self.results and (time.time() - last_activity) > 15:
                    print(f"\n✅ No activity for 15 seconds, assuming tests complete")
                    break

        except KeyboardInterrupt:
            print("\n\nInterrupted by user")
        finally:
            if process:
                process.terminate()
                process.wait()

        print(f"\n=== Capture Summary ===")
        print(f"Captured {len(self.results)} screenshots")

    def capture_screenshot(self, test_id: str) -> bool:
        """Capture a screenshot via ADB screencap."""
        local_path = self.local_screenshot_dir / f"{test_id}.png"

        try:
            # Capture screenshot directly to local file
            result = subprocess.run(
                ["adb", "exec-out", "screencap", "-p"],
                capture_output=True,
                check=True,
                timeout=5
            )

            # Write to file
            with open(local_path, 'wb') as f:
                f.write(result.stdout)

            print(f"    Saved to: {local_path}")
            return True

        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
            print(f"    ✗ Failed: {e}")
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

        html_content = f"""<!DOCTYPE html>
<html>
<head>
    <title>Ghostty Visual Test Results</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 40px;
            background: #f5f5f5;
        }}
        h1 {{ color: #333; }}
        .test-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(400px, 1fr));
            gap: 20px;
            margin-top: 30px;
        }}
        .test-card {{
            background: white;
            border-radius: 8px;
            padding: 15px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }}
        .test-card h3 {{
            margin-top: 0;
            color: #444;
            font-size: 16px;
            font-family: monospace;
        }}
        .test-card img {{
            width: 100%;
            border: 1px solid #ddd;
            border-radius: 4px;
        }}
        .test-card .timestamp {{
            color: #888;
            font-size: 12px;
            margin-top: 10px;
        }}
    </style>
</head>
<body>
    <h1>Ghostty Visual Test Results</h1>
    <p>Generated: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}</p>
    <p>Total tests: {len(self.results)}</p>

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
            f.write(html_content)

        print(f"HTML index saved to: {html_path}")
        print(f"\nView results: file://{html_path.absolute()}")


def main():
    parser = argparse.ArgumentParser(
        description="Run visual regression tests for Ghostty Android (Simple Version)"
    )
    parser.add_argument(
        "--output", "-o",
        required=True,
        help="Output directory for screenshots and reports"
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
    parser.add_argument(
        "--no-launch",
        action="store_true",
        help="Don't launch the app, just monitor for tests"
    )
    parser.add_argument(
        "--tag",
        help="Run only tests with this tag (e.g., color, cursor)"
    )

    args = parser.parse_args()

    # Create test runner
    runner = SimpleTestRunner(args.output, args.package)

    # Check ADB connection
    if not runner.check_adb_connection():
        sys.exit(1)

    # Launch app (unless --no-launch)
    if not args.no_launch:
        if not runner.launch_app_in_test_mode(test_tag=args.tag):
            sys.exit(1)

        print("\nWaiting for app to start...")
        time.sleep(2)

    # Monitor and capture screenshots
    runner.monitor_and_capture(timeout=args.timeout)

    # Generate report
    if runner.results:
        runner.generate_report()
        print("\n✅ Visual test run completed!")
    else:
        print("\n⚠️  No tests were captured. Make sure to start tests in the app.")
        sys.exit(1)


if __name__ == "__main__":
    main()
