"""
Test runner for visual regression tests.

This module discovers and executes visual regression tests,
comparing rendered output against reference screenshots.
"""

import sys
import time
from pathlib import Path
from typing import List, Optional, Dict
from dataclasses import dataclass, field
from datetime import datetime

# Add current directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from test_case import TestCase
from adb_controller import ADBController
from image_compare import compare_images, ComparisonResult


@dataclass
class TestResult:
    """Result of a single test execution."""
    test_case: TestCase
    passed: bool
    comparison: Optional[ComparisonResult] = None
    error: Optional[str] = None
    duration_seconds: float = 0.0
    actual_screenshot: Optional[Path] = None

    @property
    def status(self) -> str:
        """Get status string for display."""
        if self.error:
            return "ERROR"
        elif self.passed:
            return "PASS"
        else:
            return "FAIL"


@dataclass
class TestRunSummary:
    """Summary of entire test run."""
    total: int = 0
    passed: int = 0
    failed: int = 0
    errors: int = 0
    duration_seconds: float = 0.0
    results: List[TestResult] = field(default_factory=list)

    @property
    def success_rate(self) -> float:
        """Calculate success rate (0.0 to 1.0)."""
        if self.total == 0:
            return 0.0
        return self.passed / self.total


class TestRunner:
    """
    Visual regression test runner.

    Executes tests on Android device via ADB and compares screenshots
    with reference images.
    """

    def __init__(
        self,
        adb: ADBController,
        output_dir: Path,
        pixel_threshold: int = 0
    ):
        """
        Initialize test runner.

        Args:
            adb: ADB controller for device interaction
            output_dir: Directory for test output (screenshots, diffs, reports)
            pixel_threshold: Pixel difference threshold for pass/fail (0 = exact)
        """
        self.adb = adb
        self.output_dir = output_dir
        self.pixel_threshold = pixel_threshold

        # Create output directories
        self.screenshots_dir = output_dir / "screenshots"
        self.diffs_dir = output_dir / "diffs"
        self.screenshots_dir.mkdir(parents=True, exist_ok=True)
        self.diffs_dir.mkdir(parents=True, exist_ok=True)

    def run_test(self, test: TestCase) -> TestResult:
        """
        Execute a single test case.

        Args:
            test: Test case to execute

        Returns:
            TestResult with execution results
        """
        print(f"  Running: {test.name} ... ", end="", flush=True)
        start_time = time.time()

        try:
            # Ensure app is running
            if not self.adb.is_app_running():
                if not self.adb.launch_app():
                    raise RuntimeError("Failed to launch app")

            # Execute test actions
            for action in test.actions:
                if not self.adb.execute_action(action):
                    raise RuntimeError(f"Failed to execute action: {action}")

            # Give final render time to complete
            time.sleep(0.5)

            # Capture screenshot
            screenshot_path = self.screenshots_dir / f"{test.name}.actual.png"
            if not self.adb.capture_screenshot(screenshot_path):
                raise RuntimeError("Failed to capture screenshot")

            # Compare with reference if available
            if test.reference_image and test.reference_image.exists():
                diff_path = self.diffs_dir / f"{test.name}.diff.png"
                comparison = compare_images(
                    actual=screenshot_path,
                    expected=test.reference_image,
                    diff_output=diff_path,
                    threshold=self.pixel_threshold
                )

                duration = time.time() - start_time
                result = TestResult(
                    test_case=test,
                    passed=comparison.pass_test,
                    comparison=comparison,
                    duration_seconds=duration,
                    actual_screenshot=screenshot_path
                )

                # Print result
                if result.passed:
                    print(f"✓ PASS ({duration:.2f}s)")
                else:
                    print(f"✗ FAIL (diff: {comparison.pixel_diff} pixels, {duration:.2f}s)")

                return result
            else:
                # No reference image - consider this a pass but note it
                duration = time.time() - start_time
                print(f"⚠ PASS (no reference, {duration:.2f}s)")
                return TestResult(
                    test_case=test,
                    passed=True,
                    duration_seconds=duration,
                    actual_screenshot=screenshot_path
                )

        except Exception as e:
            duration = time.time() - start_time
            error_msg = str(e)
            print(f"✗ ERROR: {error_msg} ({duration:.2f}s)")
            return TestResult(
                test_case=test,
                passed=False,
                error=error_msg,
                duration_seconds=duration
            )

    def run_tests(self, tests: List[TestCase], stop_on_failure: bool = False) -> TestRunSummary:
        """
        Run multiple test cases.

        Args:
            tests: List of test cases to execute
            stop_on_failure: Stop execution on first failure if True

        Returns:
            TestRunSummary with results
        """
        summary = TestRunSummary(total=len(tests))
        start_time = time.time()

        print(f"\n{'='*70}")
        print(f"Running {len(tests)} visual regression tests")
        print(f"Device: {self.adb.device_serial or 'default'}")
        print(f"Output: {self.output_dir}")
        print(f"Threshold: {self.pixel_threshold} pixels")
        print(f"{'='*70}\n")

        for i, test in enumerate(tests, 1):
            print(f"[{i}/{len(tests)}] ", end="")

            result = self.run_test(test)
            summary.results.append(result)

            if result.error:
                summary.errors += 1
            elif result.passed:
                summary.passed += 1
            else:
                summary.failed += 1

            # Stop on failure if requested
            if stop_on_failure and not result.passed:
                print(f"\n⚠ Stopping on failure as requested\n")
                break

        summary.duration_seconds = time.time() - start_time

        # Print summary
        self._print_summary(summary)

        return summary

    def _print_summary(self, summary: TestRunSummary):
        """Print test run summary."""
        print(f"\n{'='*70}")
        print(f"Test Summary")
        print(f"{'='*70}")
        print(f"Total:    {summary.total}")
        print(f"Passed:   {summary.passed} ✓")
        print(f"Failed:   {summary.failed} ✗")
        print(f"Errors:   {summary.errors} ⚠")
        print(f"Success:  {summary.success_rate*100:.1f}%")
        print(f"Duration: {summary.duration_seconds:.2f}s")
        print(f"{'='*70}\n")

        # Print failed tests details
        if summary.failed > 0 or summary.errors > 0:
            print("Failed/Error Tests:")
            for result in summary.results:
                if not result.passed:
                    print(f"  ✗ {result.test_case.name}")
                    if result.error:
                        print(f"    Error: {result.error}")
                    elif result.comparison:
                        print(f"    Diff: {result.comparison.pixel_diff} pixels")
                        if result.comparison.diff_image:
                            print(f"    Diff image: {result.comparison.diff_image}")
            print()

    def cleanup(self):
        """Cleanup resources."""
        # Stop app
        self.adb.stop_app()


def discover_tests(tests_dir: Path) -> List[TestCase]:
    """
    Discover all test cases in a directory.

    Args:
        tests_dir: Directory containing test modules

    Returns:
        List of discovered test cases
    """
    # This will be implemented by test definition modules
    # For now, return empty list
    return []
