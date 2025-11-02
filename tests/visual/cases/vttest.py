"""
VT Test Suite cases.

Converted from libghostty-vt/test/cases/vttest/*.sh

These tests exercise the vttest program which is the VT100/VT220/VT320
test suite. Each test navigates through the vttest menu to a specific
test and captures the rendered output.
"""

import sys
from pathlib import Path
from typing import List

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from test_case import TestCase
from cases import REFERENCE_DIR


def get_tests() -> List[TestCase]:
    """Get all vttest test cases."""
    return [
        test_vttest_launch(),
        test_vttest_1_1(),
        test_vttest_1_2(),
        test_vttest_1_3(),
        test_vttest_1_4(),
        test_vttest_1_5(),
        test_vttest_1_6(),
    ]


def test_vttest_launch() -> TestCase:
    """
    VT Test: Launch menu

    Original: libghostty-vt/test/cases/vttest/launch.sh
    Tests basic vttest launch and menu display.
    """
    test = TestCase(
        name="vttest_launch",
        description="VT Test - Launch menu display"
    )

    # xdotool type "vttest"
    test.add_type("vttest")

    # xdotool key Return
    test.add_key("Return")

    # sleep 1
    test.add_sleep(1.0)

    # Set reference image
    test.reference_image = REFERENCE_DIR / "vttest" / "launch.sh.ghostty.png"

    return test


def test_vttest_1_1() -> TestCase:
    """
    VT Test: Test of cursor movements (menu option 1)

    Original: libghostty-vt/test/cases/vttest/1_1.sh
    Tests cursor positioning and movement.
    """
    test = TestCase(
        name="vttest_1_1",
        description="VT Test - Cursor movements (test 1)"
    )

    # Launch vttest
    test.add_type("vttest")
    test.add_key("Return")
    test.add_sleep(1.0)

    # Select option 1
    test.add_type("1")
    test.add_key("Return")

    # Set reference image
    test.reference_image = REFERENCE_DIR / "vttest" / "1_1.sh.ghostty.png"

    return test


def test_vttest_1_2() -> TestCase:
    """
    VT Test: Test of screen features (menu option 1, subtest 2)

    Original: libghostty-vt/test/cases/vttest/1_2.sh
    Tests screen clearing, scrolling, and other display features.
    """
    test = TestCase(
        name="vttest_1_2",
        description="VT Test - Screen features (test 1.2)"
    )

    # Launch vttest and select option 1
    test.add_type("vttest")
    test.add_key("Return")
    test.add_sleep(1.0)
    test.add_type("1")
    test.add_key("Return")

    # Navigate to subtest (press Return to advance)
    test.add_sleep(0.5)
    test.add_key("Return")

    # Set reference image
    test.reference_image = REFERENCE_DIR / "vttest" / "1_2.sh.ghostty.png"

    return test


def test_vttest_1_3() -> TestCase:
    """
    VT Test: Test of character sets (menu option 1, subtest 3)

    Original: libghostty-vt/test/cases/vttest/1_3.sh
    Tests character set handling and rendering.
    """
    test = TestCase(
        name="vttest_1_3",
        description="VT Test - Character sets (test 1.3)"
    )

    # Launch vttest and select option 1
    test.add_type("vttest")
    test.add_key("Return")
    test.add_sleep(1.0)
    test.add_type("1")
    test.add_key("Return")

    # Navigate to subtest 3 (press Return twice)
    test.add_sleep(0.5)
    test.add_key("Return")
    test.add_sleep(0.5)
    test.add_key("Return")

    # Set reference image
    test.reference_image = REFERENCE_DIR / "vttest" / "1_3.sh.ghostty.png"

    return test


def test_vttest_1_4() -> TestCase:
    """
    VT Test: Test of double-sized characters (menu option 1, subtest 4)

    Original: libghostty-vt/test/cases/vttest/1_4.sh
    Tests double-width and double-height character rendering.
    """
    test = TestCase(
        name="vttest_1_4",
        description="VT Test - Double-sized characters (test 1.4)"
    )

    # Launch vttest and select option 1
    test.add_type("vttest")
    test.add_key("Return")
    test.add_sleep(1.0)
    test.add_type("1")
    test.add_key("Return")

    # Navigate to subtest 4 (press Return 3 times)
    test.add_sleep(0.5)
    test.add_key("Return")
    test.add_sleep(0.5)
    test.add_key("Return")
    test.add_sleep(0.5)
    test.add_key("Return")

    # Set reference image
    test.reference_image = REFERENCE_DIR / "vttest" / "1_4.sh.ghostty.png"

    return test


def test_vttest_1_5() -> TestCase:
    """
    VT Test: Test of keyboard (menu option 1, subtest 5)

    Original: libghostty-vt/test/cases/vttest/1_5.sh
    Tests keyboard input and key mapping.
    """
    test = TestCase(
        name="vttest_1_5",
        description="VT Test - Keyboard test (test 1.5)"
    )

    # Launch vttest and select option 1
    test.add_type("vttest")
    test.add_key("Return")
    test.add_sleep(1.0)
    test.add_type("1")
    test.add_key("Return")

    # Navigate to subtest 5 (press Return 4 times)
    test.add_sleep(0.5)
    test.add_key("Return")
    test.add_sleep(0.5)
    test.add_key("Return")
    test.add_sleep(0.5)
    test.add_key("Return")
    test.add_sleep(0.5)
    test.add_key("Return")

    # Set reference image
    test.reference_image = REFERENCE_DIR / "vttest" / "1_5.sh.ghostty.png"

    return test


def test_vttest_1_6() -> TestCase:
    """
    VT Test: Test of terminal reports (menu option 1, subtest 6)

    Original: libghostty-vt/test/cases/vttest/1_6.sh
    Tests terminal status reporting and query responses.
    """
    test = TestCase(
        name="vttest_1_6",
        description="VT Test - Terminal reports (test 1.6)"
    )

    # Launch vttest and select option 1
    test.add_type("vttest")
    test.add_key("Return")
    test.add_sleep(1.0)
    test.add_type("1")
    test.add_key("Return")

    # Navigate to subtest 6 (press Return 5 times)
    test.add_sleep(0.5)
    test.add_key("Return")
    test.add_sleep(0.5)
    test.add_key("Return")
    test.add_sleep(0.5)
    test.add_key("Return")
    test.add_sleep(0.5)
    test.add_key("Return")
    test.add_sleep(0.5)
    test.add_key("Return")

    # Set reference image
    test.reference_image = REFERENCE_DIR / "vttest" / "1_6.sh.ghostty.png"

    return test
