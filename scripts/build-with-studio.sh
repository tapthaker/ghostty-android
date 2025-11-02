#!/usr/bin/env bash
# Helper script to build Ghostty Android APK using Android Studio
# This works around NixOS AAPT2 compatibility issues

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ANDROID_DIR="$PROJECT_ROOT/android"

echo "=================================="
echo "Ghostty Android - Studio Build"
echo "=================================="
echo ""

# Check if we're on NixOS
if [ -f /etc/NIXOS ]; then
    echo "✓ NixOS detected - using Android Studio is recommended"
    echo ""
fi

# Check if Android Studio is available
if command -v android-studio &> /dev/null; then
    STUDIO_CMD="android-studio"
elif command -v studio &> /dev/null; then
    STUDIO_CMD="studio"
elif command -v studio.sh &> /dev/null; then
    STUDIO_CMD="studio.sh"
else
    echo "❌ Android Studio not found in PATH"
    echo ""
    echo "Install with:"
    echo "  nix-shell -p android-studio"
    echo "Or add to your NixOS configuration:"
    echo "  environment.systemPackages = [ pkgs.android-studio ];"
    echo ""
    exit 1
fi

echo "Found Android Studio: $STUDIO_CMD"
echo ""
echo "Opening project in Android Studio..."
echo "  Project: $ANDROID_DIR"
echo ""
echo "Steps to build in Android Studio:"
echo "  1. Wait for Gradle sync to complete"
echo "  2. Build → Make Project (or Ctrl+F9)"
echo "  3. Build → Build Bundle(s) / APK(s) → Build APK(s)"
echo "  4. APK will be at: android/app/build/outputs/apk/debug/app-debug.apk"
echo ""
echo "Or use the Gradle panel on the right:"
echo "  app → Tasks → build → assembleDebug"
echo ""

# Open Android Studio
"$STUDIO_CMD" "$ANDROID_DIR" &

echo "Android Studio launched!"
echo ""
echo "Alternative: Build from Android Studio terminal:"
echo "  cd $ANDROID_DIR"
echo "  ./gradlew assembleDebug"
echo ""
