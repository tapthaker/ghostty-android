"""
Line wrapping test case.

Converted from libghostty-vt/test/cases/wraptest.sh

This test exercises the wraptest program which displays a matrix
of different line wrapping scenarios.
"""

import sys
from pathlib import Path
from typing import List

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from test_case import TestCase
from cases import REFERENCE_DIR


def get_tests() -> List[TestCase]:
    """Get wraptest test cases."""
    return [
        test_wraptest(),
    ]


def test_wraptest() -> TestCase:
    """
    Line wrapping test

    Original: libghostty-vt/test/cases/wraptest.sh
    Tests various line wrapping behaviors with a matrix of scenarios.
    """
    test = TestCase(
        name="wraptest",
        description="Line wrapping test matrix"
    )

    # xdotool type "wraptest"
    test.add_type("wraptest")

    # xdotool key Return
    test.add_key("Return")

    # Set reference image
    test.reference_image = REFERENCE_DIR / "wraptest.sh.ghostty.png"

    return test
