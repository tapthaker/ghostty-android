#!/usr/bin/env bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command-line arguments
INSTALL_APK=false
for arg in "$@"; do
    case $arg in
        --install|-i)
            INSTALL_APK=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --install, -i    Install APK on connected device after build"
            echo "  --help, -h       Show this help message"
            echo ""
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $arg${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}  Building Ghostty Android App${NC}"
echo -e "${BLUE}===================================================${NC}"
echo ""

# Determine script location and project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/../.." && pwd )"
ANDROID_DIR="${PROJECT_ROOT}/android"

echo "Project root: ${PROJECT_ROOT}"
echo "Android dir: ${ANDROID_DIR}"
echo ""

# Step 1: Build Android APK (native libraries built via Gradle preBuild task)
echo -e "${BLUE}Step 1: Building Android APK...${NC}"
echo -e "${BLUE}===================================================${NC}"
echo ""

cd "${ANDROID_DIR}"

echo "Running Gradle build..."
./gradlew assembleDebug

echo ""
echo -e "${GREEN}===================================================${NC}"
echo -e "${GREEN}  Build Complete!${NC}"
echo -e "${GREEN}===================================================${NC}"
echo ""
echo "Native libraries: android/app/src/main/jniLibs/"
echo "APK location:     android/app/build/outputs/apk/debug/app-debug.apk"
echo ""

# Install APK if --install flag was provided
if [ "$INSTALL_APK" = true ]; then
    echo -e "${BLUE}===================================================${NC}"
    echo -e "${BLUE}  Installing APK on Device${NC}"
    echo -e "${BLUE}===================================================${NC}"
    echo ""

    # Check if adb is available
    if ! command -v adb &> /dev/null; then
        echo -e "${RED}Error: adb is not installed or not in PATH${NC}"
        echo "Please install Android SDK Platform Tools"
        exit 1
    fi

    # Check if any devices are connected
    DEVICE_COUNT=$(adb devices | grep -v "List of devices" | grep -v "^$" | wc -l)
    if [ "$DEVICE_COUNT" -eq 0 ]; then
        echo -e "${RED}Error: No Android devices connected${NC}"
        echo "Please connect a device or start an emulator"
        exit 1
    fi

    echo "Installing APK on connected device(s)..."
    adb install -r "${ANDROID_DIR}/app/build/outputs/apk/debug/app-debug.apk"

    echo ""
    echo -e "${GREEN}✓ APK installed successfully${NC}"
    echo ""
    echo "View logs:"
    echo "  adb logcat | grep ghostty"
    echo ""
else
    echo "Install on device:"
    echo "  adb install -r app/build/outputs/apk/debug/app-debug.apk"
    echo ""
    echo "Or rebuild with --install flag:"
    echo "  ./android/scripts/build-android.sh --install"
    echo ""
fi
