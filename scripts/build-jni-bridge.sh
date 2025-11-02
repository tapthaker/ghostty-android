#!/usr/bin/env bash
# Build JNI bridge for Android using NDK clang

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_APP="$PROJECT_ROOT/android/app"
JNI_SRC="$ANDROID_APP/src/main/cpp/ghostty_bridge.c"
LIBGHOSTTY_INCLUDE="$PROJECT_ROOT/libghostty-vt/include"

# Get NDK path
if [ -z "$ANDROID_NDK_ROOT" ]; then
    if [ -n "$ANDROID_HOME" ]; then
        ANDROID_NDK_ROOT="$ANDROID_HOME/ndk/29.0.14206865"
    else
        ANDROID_NDK_ROOT="/home/tapan/Android/Sdk/ndk/29.0.14206865"
    fi
fi

echo -e "${BLUE}Building JNI bridge for Android${NC}"
echo "  NDK: $ANDROID_NDK_ROOT"
echo "  Source: $JNI_SRC"

# Build for each ABI
for ABI in arm64-v8a armeabi-v7a x86_64; do
    echo -e "\n${YELLOW}Building JNI bridge for $ABI...${NC}"

    OUTPUT_DIR="$ANDROID_APP/src/main/jniLibs/$ABI"
    mkdir -p "$OUTPUT_DIR"

    # Set clang compiler and target
    case "$ABI" in
        arm64-v8a)
            CLANG="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang"
            ;;
        armeabi-v7a)
            CLANG="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi24-clang"
            ;;
        x86_64)
            CLANG="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android24-clang"
            ;;
        *)
            echo -e "${RED}Unknown ABI: $ABI${NC}"
            continue
            ;;
    esac

    # Compile JNI bridge
    "$CLANG" \
        -shared \
        -fPIC \
        -I"$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include" \
        -I"$LIBGHOSTTY_INCLUDE" \
        -L"$OUTPUT_DIR" \
        -lghostty-vt \
        -llog \
        -o "$OUTPUT_DIR/libghostty_bridge.so" \
        "$JNI_SRC"

    if [ -f "$OUTPUT_DIR/libghostty_bridge.so" ]; then
        echo -e "${GREEN}✓ Built: $OUTPUT_DIR/libghostty_bridge.so${NC}"
    else
        echo -e "${RED}✗ Failed to build JNI bridge for $ABI${NC}"
        exit 1
    fi
done

echo -e "\n${GREEN}✓ All JNI bridges built successfully${NC}"
