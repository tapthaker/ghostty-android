"""
Test case definition for visual regression tests.

This module defines the TestCase class that represents a single
visual regression test with keyboard actions and expected output.
"""

from dataclasses import dataclass, field
from enum import Enum
from typing import List, Optional
from pathlib import Path


class KeyAction(Enum):
    """Keyboard action types."""
    TYPE = "type"  # Type text
    KEY = "key"    # Press special key
    SLEEP = "sleep"  # Wait


@dataclass
class Action:
    """A single keyboard action in a test."""
    action_type: KeyAction
    value: str

    def __repr__(self) -> str:
        return f"{self.action_type.value}({self.value!r})"


@dataclass
class TestCase:
    """
    A visual regression test case.

    Attributes:
        name: Test name (e.g., "vttest_1_1")
        description: Human-readable description
        actions: List of keyboard actions to perform
        reference_image: Path to reference screenshot (*.ghostty.png)
        timeout: Maximum time to wait for test completion (seconds)
    """
    name: str
    description: str
    actions: List[Action] = field(default_factory=list)
    reference_image: Optional[Path] = None
    timeout: float = 10.0

    def add_type(self, text: str) -> "TestCase":
        """Add a text typing action."""
        self.actions.append(Action(KeyAction.TYPE, text))
        return self

    def add_key(self, key: str) -> "TestCase":
        """Add a special key press (Return, Up, Down, etc.)."""
        self.actions.append(Action(KeyAction.KEY, key))
        return self

    def add_sleep(self, seconds: float) -> "TestCase":
        """Add a sleep/wait action."""
        self.actions.append(Action(KeyAction.SLEEP, str(seconds)))
        return self

    def __repr__(self) -> str:
        return f"TestCase({self.name!r}, {len(self.actions)} actions)"
