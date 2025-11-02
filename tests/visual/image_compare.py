"""
Image comparison utilities for visual regression testing.

This module provides functions to compare screenshots with reference images
and calculate difference metrics.
"""

from pathlib import Path
from typing import Tuple, Optional
from dataclasses import dataclass
import subprocess


@dataclass
class ComparisonResult:
    """Result of comparing two images."""
    pixel_diff: int  # Number of different pixels (Absolute Error metric)
    is_match: bool   # True if images match (diff == 0)
    diff_image: Optional[Path] = None  # Path to diff visualization (if generated)

    @property
    def pass_test(self) -> bool:
        """Returns True if test passes (images match)."""
        return self.is_match


class ImageCompare:
    """
    Image comparison using ImageMagick (same as Ghostty OSS tests).
    """

    @staticmethod
    def compare(
        actual: Path,
        expected: Path,
        diff_output: Optional[Path] = None,
        threshold: int = 0
    ) -> ComparisonResult:
        """
        Compare two images using ImageMagick's Absolute Error (AE) metric.

        This matches the comparison method used in Ghostty's test/run.sh:
        `compare -metric AE actual.png expected.png null:`

        Args:
            actual: Path to actual screenshot
            expected: Path to expected/reference screenshot
            diff_output: Optional path to save diff visualization
            threshold: Pixel difference threshold (0 = exact match required)

        Returns:
            ComparisonResult with pixel diff count and match status
        """
        if not actual.exists():
            raise FileNotFoundError(f"Actual image not found: {actual}")
        if not expected.exists():
            raise FileNotFoundError(f"Expected image not found: {expected}")

        # Build ImageMagick compare command
        diff_target = str(diff_output) if diff_output else "null:"
        cmd = [
            "compare",
            "-metric", "AE",  # Absolute Error metric
            str(actual),
            str(expected),
            diff_target
        ]

        try:
            # ImageMagick outputs metric to stderr
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=False  # Don't raise on non-zero exit (exit 1 = images differ)
            )

            # Exit code 2 = error, 1 = different, 0 = same
            if result.returncode == 2:
                raise RuntimeError(f"ImageMagick compare failed: {result.stderr}")

            # Parse pixel difference from stderr
            try:
                pixel_diff = int(result.stderr.strip())
            except ValueError:
                raise RuntimeError(f"Failed to parse diff count: {result.stderr}")

            return ComparisonResult(
                pixel_diff=pixel_diff,
                is_match=(pixel_diff <= threshold),
                diff_image=diff_output if diff_output and pixel_diff > 0 else None
            )

        except FileNotFoundError:
            raise RuntimeError(
                "ImageMagick not found. Please install: sudo apt-get install imagemagick"
            )

    @staticmethod
    def check_imagemagick() -> bool:
        """Check if ImageMagick is available."""
        try:
            result = subprocess.run(
                ["compare", "-version"],
                capture_output=True,
                check=False
            )
            return result.returncode == 0
        except FileNotFoundError:
            return False


# Alternative: PIL/Pillow-based comparison (no external deps)
try:
    from PIL import Image, ImageChops
    import numpy as np

    class PillowImageCompare:
        """
        Image comparison using PIL/Pillow (pure Python, no external tools).

        This is an alternative to ImageMagick for environments where
        ImageMagick is not available.
        """

        @staticmethod
        def compare(
            actual: Path,
            expected: Path,
            diff_output: Optional[Path] = None,
            threshold: int = 0
        ) -> ComparisonResult:
            """
            Compare two images using PIL/Pillow.

            Args:
                actual: Path to actual screenshot
                expected: Path to expected/reference screenshot
                diff_output: Optional path to save diff visualization
                threshold: Pixel difference threshold

            Returns:
                ComparisonResult with pixel diff count and match status
            """
            if not actual.exists():
                raise FileNotFoundError(f"Actual image not found: {actual}")
            if not expected.exists():
                raise FileNotFoundError(f"Expected image not found: {expected}")

            # Load images
            img1 = Image.open(actual).convert("RGB")
            img2 = Image.open(expected).convert("RGB")

            # Check dimensions match
            if img1.size != img2.size:
                raise ValueError(
                    f"Image dimensions don't match: "
                    f"{img1.size} vs {img2.size}"
                )

            # Calculate pixel-wise difference
            diff = ImageChops.difference(img1, img2)

            # Convert to numpy for pixel counting
            diff_array = np.array(diff)

            # Count pixels with any channel difference
            # (matches ImageMagick AE metric behavior)
            pixel_diff = np.count_nonzero(diff_array.any(axis=2))

            # Save diff visualization if requested and there are differences
            if diff_output and pixel_diff > 0:
                diff_output.parent.mkdir(parents=True, exist_ok=True)
                # Enhance visibility by scaling differences
                enhanced = diff.point(lambda x: x * 10)
                enhanced.save(diff_output)

            return ComparisonResult(
                pixel_diff=pixel_diff,
                is_match=(pixel_diff <= threshold),
                diff_image=diff_output if diff_output and pixel_diff > 0 else None
            )

except ImportError:
    # PIL not available, only ImageMagick comparison will work
    PillowImageCompare = None


def compare_images(
    actual: Path,
    expected: Path,
    diff_output: Optional[Path] = None,
    threshold: int = 0,
    prefer_imagemagick: bool = True
) -> ComparisonResult:
    """
    Compare two images, automatically selecting best available method.

    Prefers ImageMagick (to match Ghostty OSS tests) but falls back
    to PIL/Pillow if ImageMagick is not available.

    Args:
        actual: Path to actual screenshot
        expected: Path to expected/reference screenshot
        diff_output: Optional path to save diff visualization
        threshold: Pixel difference threshold (0 = exact match)
        prefer_imagemagick: Try ImageMagick first if True

    Returns:
        ComparisonResult with pixel diff count and match status
    """
    if prefer_imagemagick and ImageCompare.check_imagemagick():
        return ImageCompare.compare(actual, expected, diff_output, threshold)
    elif PillowImageCompare is not None:
        return PillowImageCompare.compare(actual, expected, diff_output, threshold)
    else:
        raise RuntimeError(
            "No image comparison tool available. "
            "Install either ImageMagick or PIL/Pillow."
        )
