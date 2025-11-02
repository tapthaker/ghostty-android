"""
Test case definitions converted from Ghostty OSS visual regression tests.

This package contains all the test cases from libghostty-vt/test/cases/
converted to Python format.
"""

import sys
from pathlib import Path
from typing import List

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from test_case import TestCase


# Base directory for reference images
REFERENCE_DIR = Path(__file__).parent.parent.parent.parent / "libghostty-vt" / "test" / "cases"


def get_all_tests() -> List[TestCase]:
    """Get all available test cases."""
    from . import vttest, wraptest

    tests = []
    tests.extend(vttest.get_tests())
    tests.extend(wraptest.get_tests())

    return tests
