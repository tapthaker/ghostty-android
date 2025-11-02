"""
ADB controller for interacting with Ghostty Android app.

This module provides an interface to control the Android app via ADB,
send keyboard input, and capture screenshots.
"""

import sys
import subprocess
import time
from pathlib import Path
from typing import Optional, List

# Add current directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from test_case import Action, KeyAction


class ADBController:
    """
    Controller for interacting with Android device via ADB.
    """

    PACKAGE_NAME = "com.ghostty.android"
    ACTIVITY_NAME = f"{PACKAGE_NAME}/.MainActivity"

    def __init__(self, device_serial: Optional[str] = None):
        """
        Initialize ADB controller.

        Args:
            device_serial: Optional device serial number. If None, uses default device.
        """
        self.device_serial = device_serial
        self._base_cmd = ["adb"]
        if device_serial:
            self._base_cmd.extend(["-s", device_serial])

    def _run(self, cmd: List[str], check: bool = True, capture_output: bool = True) -> subprocess.CompletedProcess:
        """Run an ADB command."""
        full_cmd = self._base_cmd + cmd
        return subprocess.run(
            full_cmd,
            check=check,
            capture_output=capture_output,
            text=True
        )

    def check_device(self) -> bool:
        """Check if device is connected and responsive."""
        try:
            result = self._run(["get-state"], check=False)
            return result.returncode == 0 and result.stdout.strip() == "device"
        except Exception:
            return False

    def get_app_pid(self) -> Optional[int]:
        """Get the PID of the running Ghostty app, or None if not running."""
        result = self._run(
            ["shell", "pidof", "-s", self.PACKAGE_NAME],
            check=False
        )
        if result.returncode == 0 and result.stdout.strip():
            return int(result.stdout.strip())
        return None

    def is_app_running(self) -> bool:
        """Check if Ghostty app is running."""
        return self.get_app_pid() is not None

    def launch_app(self, wait_seconds: float = 2.0) -> bool:
        """
        Launch the Ghostty app.

        Args:
            wait_seconds: Time to wait after launching

        Returns:
            True if app launched successfully
        """
        try:
            self._run([
                "shell", "am", "start",
                "-n", self.ACTIVITY_NAME,
                "-a", "android.intent.action.MAIN",
                "-c", "android.intent.category.LAUNCHER"
            ])
            time.sleep(wait_seconds)
            return self.is_app_running()
        except Exception as e:
            print(f"Failed to launch app: {e}")
            return False

    def stop_app(self) -> bool:
        """Stop the Ghostty app."""
        try:
            self._run(["shell", "am", "force-stop", self.PACKAGE_NAME])
            time.sleep(0.5)
            return not self.is_app_running()
        except Exception:
            return False

    def clear_app_data(self) -> bool:
        """Clear app data and cache."""
        try:
            self._run(["shell", "pm", "clear", self.PACKAGE_NAME])
            return True
        except Exception:
            return False

    def send_text(self, text: str) -> bool:
        """
        Send text input to the app.

        Args:
            text: Text to send (special chars will be escaped)

        Returns:
            True if successful
        """
        # Escape special characters for shell
        escaped = text.replace(" ", "%s").replace("'", "\\'")
        try:
            self._run(["shell", "input", "text", escaped])
            return True
        except Exception as e:
            print(f"Failed to send text {text!r}: {e}")
            return False

    def send_key(self, key: str) -> bool:
        """
        Send a special key press.

        Args:
            key: Key name (e.g., "ENTER", "TAB", "DPAD_UP")

        Returns:
            True if successful
        """
        # Map xdotool key names to Android key codes
        key_map = {
            "Return": "ENTER",
            "Enter": "ENTER",
            "Tab": "TAB",
            "Escape": "ESCAPE",
            "Up": "DPAD_UP",
            "Down": "DPAD_DOWN",
            "Left": "DPAD_LEFT",
            "Right": "DPAD_RIGHT",
            "BackSpace": "DEL",
            "Delete": "FORWARD_DEL",
        }

        android_key = key_map.get(key, key.upper())

        try:
            self._run(["shell", "input", "keyevent", android_key])
            return True
        except Exception as e:
            print(f"Failed to send key {key!r}: {e}")
            return False

    def execute_action(self, action: Action) -> bool:
        """
        Execute a single test action.

        Args:
            action: Action to execute

        Returns:
            True if successful
        """
        if action.action_type == KeyAction.TYPE:
            return self.send_text(action.value)
        elif action.action_type == KeyAction.KEY:
            return self.send_key(action.value)
        elif action.action_type == KeyAction.SLEEP:
            time.sleep(float(action.value))
            return True
        else:
            print(f"Unknown action type: {action.action_type}")
            return False

    def capture_screenshot(self, output_path: Path) -> bool:
        """
        Capture a screenshot from the device.

        Args:
            output_path: Where to save the screenshot (PNG)

        Returns:
            True if successful
        """
        try:
            # Use screencap to capture, then pull
            device_path = "/sdcard/ghostty_test_screenshot.png"

            # Capture screenshot on device
            self._run(["shell", "screencap", "-p", device_path])

            # Pull to local filesystem
            output_path.parent.mkdir(parents=True, exist_ok=True)
            self._run(["pull", device_path, str(output_path)])

            # Clean up device
            self._run(["shell", "rm", device_path])

            return output_path.exists()
        except Exception as e:
            print(f"Failed to capture screenshot: {e}")
            return False

    def get_logs(self, filter_tags: Optional[List[str]] = None) -> str:
        """
        Get logcat output for the app.

        Args:
            filter_tags: Optional list of log tags to filter

        Returns:
            Log output as string
        """
        try:
            # Clear old logs first
            self._run(["logcat", "-c"], check=False)

            # Get logs for our app's PID
            pid = self.get_app_pid()
            if pid:
                result = self._run(
                    ["logcat", "-d", "--pid", str(pid)],
                    check=False
                )
                return result.stdout
            return ""
        except Exception as e:
            print(f"Failed to get logs: {e}")
            return ""
