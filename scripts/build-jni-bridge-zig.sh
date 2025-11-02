#!/usr/bin/env bash
# Build JNI bridge for Android using Zig

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

# Get NDK path for libc config
if [ -z "$ANDROID_NDK_ROOT" ]; then
    if [ -n "$ANDROID_HOME" ]; then
        ANDROID_NDK_ROOT="$ANDROID_HOME/ndk/29.0.14206865"
    else
        ANDROID_NDK_ROOT="/home/tapan/Android/Sdk/ndk/29.0.14206865"
    fi
fi

echo -e "${BLUE}Building JNI bridge for Android with Zig${NC}"
echo "  Source: $JNI_SRC"

# Enter Ghostty's nix-shell to get Zig
cd "$PROJECT_ROOT/libghostty-vt"

# Build for each ABI
for ABI in arm64-v8a armeabi-v7a x86_64; do
    echo -e "\n${YELLOW}Building JNI bridge for $ABI...${NC}"

    OUTPUT_DIR="$ANDROID_APP/src/main/jniLibs/$ABI"
    mkdir -p "$OUTPUT_DIR"

    # Set Zig target and libc config
    case "$ABI" in
        arm64-v8a)
            ZIG_TARGET="aarch64-linux-android"
            LIBC_FILE="$PROJECT_ROOT/build/android-arm64-v8a-libc.txt"
            NDK_LIB_DIR="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/24"
            ;;
        armeabi-v7a)
            ZIG_TARGET="arm-linux-androideabi"
            LIBC_FILE="$PROJECT_ROOT/build/android-armeabi-v7a-libc.txt"
            NDK_LIB_DIR="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/arm-linux-androideabi/24"
            ;;
        x86_64)
            ZIG_TARGET="x86_64-linux-android"
            LIBC_FILE="$PROJECT_ROOT/build/android-x86_64-libc.txt"
            NDK_LIB_DIR="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/x86_64-linux-android/24"
            ;;
        *)
            echo -e "${RED}Unknown ABI: $ABI${NC}"
            continue
            ;;
    esac

    # Check if libc config exists
    if [ ! -f "$LIBC_FILE" ]; then
        echo -e "${RED}✗ Libc config not found: $LIBC_FILE${NC}"
        echo -e "${YELLOW}  Run 'make build-abi ABI=$ABI' first to generate it${NC}"
        exit 1
    fi

    # Compile JNI bridge with Zig (using nix-shell from libghostty-vt)
    nix-shell --run "zig build-lib \
        -target ${ZIG_TARGET}.24 \
        -dynamic \
        -fPIC \
        -I\"$LIBGHOSTTY_INCLUDE\" \
        -L\"$OUTPUT_DIR\" \
        -L\"$NDK_LIB_DIR\" \
        -lghostty-vt \
        -llog \
        --libc \"$LIBC_FILE\" \
        --name ghostty_bridge \
        \"$JNI_SRC\" && \
        mv libghostty_bridge.so \"$OUTPUT_DIR/\"" 2>&1

    if [ -f "$OUTPUT_DIR/libghostty_bridge.so" ]; then
        echo -e "${GREEN}✓ Built: $OUTPUT_DIR/libghostty_bridge.so${NC}"
        # Show file size
        ls -lh "$OUTPUT_DIR/libghostty_bridge.so" | awk '{print "  Size: " $5}'
    else
        echo -e "${RED}✗ Failed to build JNI bridge for $ABI${NC}"
        exit 1
    fi
done

echo -e "\n${GREEN}✓ All JNI bridges built successfully${NC}"
echo -e "\n${BLUE}Libraries location:${NC}"
echo "  $ANDROID_APP/src/main/jniLibs/"
