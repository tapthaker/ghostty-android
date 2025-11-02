#!/usr/bin/env bash
# Generate Zig libc configuration for Android NDK
#
# Usage: generate-android-libc.sh <ABI> <OUTPUT_FILE>

set -e

ABI=$1
OUTPUT_FILE=$2

if [ -z "$ABI" ] || [ -z "$OUTPUT_FILE" ]; then
    echo "Usage: $0 <ABI> <OUTPUT_FILE>"
    exit 1
fi

if [ -z "$ANDROID_NDK_ROOT" ]; then
    echo "Error: ANDROID_NDK_ROOT not set"
    exit 1
fi

# Map ABI to architecture and target triple
case $ABI in
    arm64-v8a)
        ARCH="aarch64"
        TRIPLE="aarch64-linux-android"
        ;;
    armeabi-v7a)
        ARCH="arm"
        TRIPLE="arm-linux-androideabi"
        ;;
    x86_64)
        ARCH="x86_64"
        TRIPLE="x86_64-linux-android"
        ;;
    *)
        echo "Unknown ABI: $ABI"
        exit 1
        ;;
esac

SYSROOT="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
TOOLCHAIN="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64"

# Auto-detect clang version
CLANG_VERSION=$(ls "$TOOLCHAIN/lib/clang" | head -1)

# Determine the GCC lib directory based on architecture
case $ABI in
    arm64-v8a)
        GCC_LIB_DIR="$TOOLCHAIN/lib/clang/$CLANG_VERSION/lib/linux/aarch64"
        ;;
    armeabi-v7a)
        GCC_LIB_DIR="$TOOLCHAIN/lib/clang/$CLANG_VERSION/lib/linux/armv7"
        ;;
    x86_64)
        GCC_LIB_DIR="$TOOLCHAIN/lib/clang/$CLANG_VERSION/lib/linux/x86_64"
        ;;
esac

# Create libc configuration
cat > "$OUTPUT_FILE" << EOF
# Zig libc configuration for Android NDK
# ABI: $ABI
# Architecture: $ARCH

include_dir=$SYSROOT/usr/include
sys_include_dir=$SYSROOT/usr/include/$TRIPLE
crt_dir=$SYSROOT/usr/lib/$TRIPLE/24
static_crt_dir=$GCC_LIB_DIR
msvc_lib_dir=
kernel32_lib_dir=
gcc_dir=
EOF

echo "Generated libc configuration: $OUTPUT_FILE"
