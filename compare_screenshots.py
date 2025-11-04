#!/usr/bin/env python3
"""
Screenshot Comparison Utility for Ghostty Android Visual Tests

This script helps compare screenshots from different test runs to identify
visual regressions or validate fixes.

Usage:
    python compare_screenshots.py --baseline /path/to/baseline --current /path/to/current --output /path/to/output
"""

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Dict, List, Tuple

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFont
    import numpy as np
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    print("WARNING: PIL (Pillow) not installed. Install with: pip install Pillow")
    print("Falling back to basic file comparison mode.")


class ScreenshotComparator:
    """Compare screenshots from visual regression tests."""

    def __init__(self, baseline_dir: str, current_dir: str, output_dir: str):
        self.baseline_dir = Path(baseline_dir)
        self.current_dir = Path(current_dir)
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

        self.diff_dir = self.output_dir / "diffs"
        self.diff_dir.mkdir(exist_ok=True)

        self.results: List[Dict] = []

    def compare_all(self) -> Dict:
        """Compare all screenshots in baseline and current directories."""
        print("=== Screenshot Comparison ===\n")

        baseline_files = set(f.name for f in self.baseline_dir.glob("*.png"))
        current_files = set(f.name for f in self.current_dir.glob("*.png"))

        missing_in_current = baseline_files - current_files
        new_in_current = current_files - baseline_files
        common_files = baseline_files & current_files

        print(f"Baseline screenshots: {len(baseline_files)}")
        print(f"Current screenshots: {len(current_files)}")
        print(f"Common screenshots: {len(common_files)}")
        print(f"Missing in current: {len(missing_in_current)}")
        print(f"New in current: {len(new_in_current)}\n")

        # Report missing and new files
        if missing_in_current:
            print("⚠️  Missing screenshots:")
            for filename in sorted(missing_in_current):
                print(f"  - {filename}")
                self.results.append({
                    "test": filename.replace('.png', ''),
                    "status": "missing",
                    "message": "Screenshot missing in current run"
                })
            print()

        if new_in_current:
            print("✨ New screenshots:")
            for filename in sorted(new_in_current):
                print(f"  + {filename}")
                self.results.append({
                    "test": filename.replace('.png', ''),
                    "status": "new",
                    "message": "New screenshot in current run"
                })
            print()

        # Compare common files
        if common_files:
            print("📊 Comparing screenshots...\n")
            for filename in sorted(common_files):
                self.compare_screenshot(filename)

        return self.generate_summary()

    def compare_screenshot(self, filename: str) -> None:
        """Compare a single screenshot."""
        baseline_path = self.baseline_dir / filename
        current_path = self.current_dir / filename
        test_id = filename.replace('.png', '')

        print(f"Comparing: {test_id}")

        if not HAS_PIL:
            # Fallback: simple byte comparison
            with open(baseline_path, 'rb') as f1, open(current_path, 'rb') as f2:
                baseline_bytes = f1.read()
                current_bytes = f2.read()

            if baseline_bytes == current_bytes:
                print(f"  ✓ Identical")
                self.results.append({
                    "test": test_id,
                    "status": "identical",
                    "message": "Screenshots are byte-for-byte identical"
                })
            else:
                print(f"  ✗ Different (byte comparison)")
                self.results.append({
                    "test": test_id,
                    "status": "different",
                    "message": "Screenshots differ"
                })
            return

        # Use PIL for image comparison
        try:
            baseline_img = Image.open(baseline_path)
            current_img = Image.open(current_path)

            # Check if dimensions match
            if baseline_img.size != current_img.size:
                print(f"  ✗ Different dimensions: {baseline_img.size} vs {current_img.size}")
                self.results.append({
                    "test": test_id,
                    "status": "different",
                    "message": f"Different dimensions: {baseline_img.size} vs {current_img.size}"
                })
                return

            # Calculate difference
            diff_img = ImageChops.difference(baseline_img, current_img)

            # Convert to numpy for analysis
            diff_array = np.array(diff_img)
            non_zero_pixels = np.count_nonzero(diff_array)
            total_pixels = diff_array.size

            if non_zero_pixels == 0:
                print(f"  ✓ Identical")
                self.results.append({
                    "test": test_id,
                    "status": "identical",
                    "message": "Screenshots are identical"
                })
            else:
                diff_percentage = (non_zero_pixels / total_pixels) * 100
                print(f"  ✗ Different: {diff_percentage:.2f}% of pixels differ")

                # Save diff image
                diff_output_path = self.diff_dir / f"{test_id}_diff.png"
                self.create_diff_visualization(baseline_img, current_img, diff_img, diff_output_path)

                self.results.append({
                    "test": test_id,
                    "status": "different",
                    "message": f"{diff_percentage:.2f}% of pixels differ",
                    "diff_percentage": diff_percentage,
                    "diff_image": str(diff_output_path.relative_to(self.output_dir))
                })

        except Exception as e:
            print(f"  ✗ Error comparing: {e}")
            self.results.append({
                "test": test_id,
                "status": "error",
                "message": f"Error comparing: {str(e)}"
            })

    def create_diff_visualization(self, baseline: Image.Image, current: Image.Image,
                                   diff: Image.Image, output_path: Path) -> None:
        """Create a side-by-side visualization with diff highlighting."""
        # Create a composite image: baseline | current | diff
        width, height = baseline.size
        composite = Image.new('RGB', (width * 3, height))

        # Paste baseline
        composite.paste(baseline.convert('RGB'), (0, 0))

        # Paste current
        composite.paste(current.convert('RGB'), (width, 0))

        # Create highlighted diff (amplify differences)
        diff_enhanced = diff.point(lambda p: p * 10 if p < 255 else 255)
        composite.paste(diff_enhanced.convert('RGB'), (width * 2, 0))

        # Add labels
        draw = ImageDraw.Draw(composite)
        try:
            font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 20)
        except:
            font = None

        draw.text((10, 10), "Baseline", fill='red', font=font)
        draw.text((width + 10, 10), "Current", fill='red', font=font)
        draw.text((width * 2 + 10, 10), "Difference (10x)", fill='red', font=font)

        composite.save(output_path)

    def generate_summary(self) -> Dict:
        """Generate a summary of comparison results."""
        summary = {
            "total_tests": len(self.results),
            "identical": sum(1 for r in self.results if r['status'] == 'identical'),
            "different": sum(1 for r in self.results if r['status'] == 'different'),
            "missing": sum(1 for r in self.results if r['status'] == 'missing'),
            "new": sum(1 for r in self.results if r['status'] == 'new'),
            "errors": sum(1 for r in self.results if r['status'] == 'error'),
            "results": self.results
        }

        # Save JSON report
        report_path = self.output_dir / "comparison_report.json"
        with open(report_path, 'w') as f:
            json.dump(summary, f, indent=2)

        print(f"\n=== Summary ===")
        print(f"Total tests: {summary['total_tests']}")
        print(f"  ✓ Identical: {summary['identical']}")
        print(f"  ✗ Different: {summary['different']}")
        print(f"  ⚠️  Missing: {summary['missing']}")
        print(f"  ✨ New: {summary['new']}")
        print(f"  ❌ Errors: {summary['errors']}")
        print(f"\nReport saved to: {report_path}")

        # Generate HTML report
        self.generate_html_report(summary)

        return summary

    def generate_html_report(self, summary: Dict) -> None:
        """Generate an HTML report for easy visualization."""
        html_path = self.output_dir / "comparison_report.html"

        html_content = """<!DOCTYPE html>
<html>
<head>
    <title>Ghostty Screenshot Comparison Report</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 40px;
            background: #f5f5f5;
        }
        h1 {
            color: #333;
        }
        .summary {
            background: white;
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 30px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
            margin-top: 15px;
        }
        .summary-item {
            padding: 15px;
            border-radius: 4px;
            text-align: center;
        }
        .summary-item .count {
            font-size: 32px;
            font-weight: bold;
        }
        .summary-item .label {
            font-size: 14px;
            color: #666;
            margin-top: 5px;
        }
        .identical { background: #d4edda; color: #155724; }
        .different { background: #f8d7da; color: #721c24; }
        .missing { background: #fff3cd; color: #856404; }
        .new { background: #d1ecf1; color: #0c5460; }

        .test-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(400px, 1fr));
            gap: 20px;
        }
        .test-card {
            background: white;
            border-radius: 8px;
            padding: 15px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .test-card h3 {
            margin-top: 0;
            font-family: monospace;
            font-size: 14px;
        }
        .test-card img {
            width: 100%;
            border: 1px solid #ddd;
            border-radius: 4px;
            margin-top: 10px;
        }
        .test-card .status {
            display: inline-block;
            padding: 4px 8px;
            border-radius: 4px;
            font-size: 12px;
            font-weight: bold;
            margin-bottom: 10px;
        }
        .status.identical { background: #d4edda; color: #155724; }
        .status.different { background: #f8d7da; color: #721c24; }
        .status.missing { background: #fff3cd; color: #856404; }
        .status.new { background: #d1ecf1; color: #0c5460; }
    </style>
</head>
<body>
    <h1>Ghostty Screenshot Comparison Report</h1>

    <div class="summary">
        <h2>Summary</h2>
        <div class="summary-grid">
            <div class="summary-item identical">
                <div class="count">{identical}</div>
                <div class="label">Identical</div>
            </div>
            <div class="summary-item different">
                <div class="count">{different}</div>
                <div class="label">Different</div>
            </div>
            <div class="summary-item missing">
                <div class="count">{missing}</div>
                <div class="label">Missing</div>
            </div>
            <div class="summary-item new">
                <div class="count">{new}</div>
                <div class="label">New</div>
            </div>
        </div>
    </div>

    <h2>Details</h2>
    <div class="test-grid">
"""

        for result in sorted(summary['results'], key=lambda x: (x['status'], x['test'])):
            status_class = result['status']
            test_id = result['test']

            html_content += f"""
        <div class="test-card">
            <h3>{test_id}</h3>
            <div class="status {status_class}">{status_class.upper()}</div>
            <div>{result['message']}</div>
"""

            if result.get('diff_image'):
                html_content += f"""
            <img src="{result['diff_image']}" alt="{test_id} diff">
"""

            html_content += """
        </div>
"""

        html_content += """
    </div>
</body>
</html>
"""

        with open(html_path, 'w') as f:
            f.write(html_content.format(**summary))

        print(f"HTML report saved to: {html_path}")
        print(f"\nView report: file://{html_path.absolute()}")


def main():
    parser = argparse.ArgumentParser(
        description="Compare screenshots from visual regression tests"
    )
    parser.add_argument(
        "--baseline", "-b",
        required=True,
        help="Directory containing baseline screenshots"
    )
    parser.add_argument(
        "--current", "-c",
        required=True,
        help="Directory containing current screenshots"
    )
    parser.add_argument(
        "--output", "-o",
        required=True,
        help="Output directory for comparison results"
    )

    args = parser.parse_args()

    # Check directories exist
    if not Path(args.baseline).exists():
        print(f"ERROR: Baseline directory not found: {args.baseline}")
        sys.exit(1)

    if not Path(args.current).exists():
        print(f"ERROR: Current directory not found: {args.current}")
        sys.exit(1)

    # Create comparator and run comparison
    comparator = ScreenshotComparator(args.baseline, args.current, args.output)
    summary = comparator.compare_all()

    # Exit with error if any differences found
    if summary['different'] > 0 or summary['missing'] > 0:
        print("\n⚠️  Visual differences detected!")
        sys.exit(1)
    else:
        print("\n✅ All screenshots match!")
        sys.exit(0)


if __name__ == "__main__":
    main()
