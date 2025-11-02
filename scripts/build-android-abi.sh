#!/usr/bin/env bash
# Build libghostty-vt for a specific Android ABI
#
# Usage: build-android-abi.sh <ABI> <OUTPUT_DIR>
# Example: build-android-abi.sh arm64-v8a android/app/src/main/jniLibs/arm64-v8a

set -e

ABI=$1
OUTPUT_DIR=$2

if [ -z "$ABI" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 <ABI> <OUTPUT_DIR>"
    echo "Example: $0 arm64-v8a android/app/src/main/jniLibs/arm64-v8a"
    exit 1
fi

# Check for NDK
if [ -z "$ANDROID_NDK_ROOT" ]; then
    echo "Error: ANDROID_NDK_ROOT not set"
    exit 1
fi

# Map ABI to Zig target triple
case $ABI in
    arm64-v8a)
        ZIG_TARGET="aarch64-linux-android"
        ;;
    armeabi-v7a)
        ZIG_TARGET="arm-linux-androideabi"
        ;;
    x86_64)
        ZIG_TARGET="x86_64-linux-android"
        ;;
    *)
        echo "Unknown ABI: $ABI"
        exit 1
        ;;
esac

API_LEVEL=${ANDROID_MIN_API:-24}

echo "Building libghostty-vt for Android"
echo "  ABI: $ABI"
echo "  Zig Target: $ZIG_TARGET"
echo "  API Level: $API_LEVEL"
echo "  NDK: $ANDROID_NDK_ROOT"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Generate libc configuration for Zig
BUILD_DIR="build"
mkdir -p "$BUILD_DIR"
LIBC_FILE="$BUILD_DIR/android-${ABI}-libc.txt"
./scripts/generate-android-libc.sh "$ABI" "$LIBC_FILE"

# Enter Ghostty directory
cd libghostty-vt

# The key is to provide Zig with Android NDK libc configuration
# Disable SIMD to avoid C++ dependencies that don't compile well for Android
# Use --libc flag to specify the libc configuration file
# lib-vt is the VT library without app/rendering dependencies
nix-shell --run "zig build lib-vt \
    -Dtarget=${ZIG_TARGET}.${API_LEVEL} \
    -Doptimize=ReleaseFast \
    -Dapp-runtime=none \
    -Dsimd=false \
    -Dcpu=baseline \
    --libc ../${LIBC_FILE}" 2>&1 | tee "../build/build-${ABI}.log"

echo ""
echo "Build log saved to: build/build-${ABI}.log"

# Copy the resulting library
if [ -f "zig-out/lib/libghostty-vt.so" ]; then
    cp zig-out/lib/libghostty-vt.so "../${OUTPUT_DIR}/"
    echo "✓ Built successfully: ${OUTPUT_DIR}/libghostty-vt.so"
else
    echo "Error: libghostty-vt.so not found"
    exit 1
fi

# Go back to root directory
cd ..

# Build the OpenGL ES renderer
echo ""
echo "Building ghostty_renderer for Android"
echo "  ABI: $ABI"
echo "  Zig Target: $ZIG_TARGET"

cd android/renderer

# Clean previous build artifacts to avoid using cached builds for wrong architecture
rm -rf zig-out .zig-cache

# Build the renderer with Zig
nix-shell ../../libghostty-vt/shell.nix --run "zig build \
    -Dtarget=${ZIG_TARGET}.${API_LEVEL} \
    -Doptimize=ReleaseFast \
    --libc ../../${LIBC_FILE}" 2>&1 | tee "../../build/build-renderer-${ABI}.log"

echo ""
echo "Renderer build log saved to: build/build-renderer-${ABI}.log"

# Copy the resulting renderer library
if [ -f "zig-out/lib/libghostty_renderer.so" ]; then
    cp zig-out/lib/libghostty_renderer.so "../../${OUTPUT_DIR}/"

    # Patch the library to add GLESv3 and liblog as needed libraries
    # This tells the Android dynamic linker to load these at runtime
    echo "Patching libghostty_renderer.so to add dependencies..."
    if command -v patchelf &> /dev/null; then
        patchelf --add-needed libGLESv3.so "../../${OUTPUT_DIR}/libghostty_renderer.so"
        patchelf --add-needed liblog.so "../../${OUTPUT_DIR}/libghostty_renderer.so"
        echo "✓ Added libGLESv3.so and liblog.so to DT_NEEDED section"
    else
        echo "Warning: patchelf not found, skipping library patching"
        echo "  Install with: nix-env -iA nixpkgs.patchelf"
    fi

    echo "✓ Built renderer successfully: ${OUTPUT_DIR}/libghostty_renderer.so"
else
    echo "Error: libghostty_renderer.so not found"
    exit 1
fi

cd ../..

echo ""
echo "✓ All libraries built successfully for ${ABI}"
