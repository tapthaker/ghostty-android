{ pkgs ? import <nixpkgs> {
    config = {
      android_sdk.accept_license = true;
      allowUnfree = true;
    };
  }
}:

let
  # Compose Android SDK with NDK via Nix
  androidComposition = pkgs.androidenv.composeAndroidPackages {
    # Command-line tools
    cmdLineToolsVersion = "8.0";

    # Build tools matching Android project requirements
    buildToolsVersions = [ "34.0.0" "30.0.3" ];
    platformToolsVersion = "34.0.5";

    # Platform versions (API levels)
    platformVersions = [ "34" "24" ];  # API 34 for target, API 24 for min

    # Include NDK for native builds
    includeNDK = true;
    # ndkVersions defaults to latest available in nixpkgs

    # ABI support matching project targets
    abiVersions = [ "arm64-v8a" "armeabi-v7a" "x86_64" ];

    # Don't need emulator or system images for building
    includeEmulator = false;
    includeSystemImages = false;
  };
in
pkgs.mkShell {
  name = "ghostty-android-dev";

  buildInputs = with pkgs; [
    # Android SDK (fully provisioned via Nix!)
    androidComposition.androidsdk

    # Java for Android builds
    jdk17

    # Build tools
    gnumake
    git
    curl
    wget

    # Zig will be installed separately via download
  ];

  shellHook = ''
    # Set JAVA_HOME for Gradle
    export JAVA_HOME="${pkgs.jdk17}"

    # Set Android environment variables from Nix composition
    export ANDROID_HOME="${androidComposition.androidsdk}/libexec/android-sdk"
    export ANDROID_NDK_ROOT="$ANDROID_HOME/ndk-bundle"

    # Fix AAPT2 for NixOS (solves dynamic linking issues)
    export GRADLE_OPTS="-Dorg.gradle.project.android.aapt2FromMavenOverride=$ANDROID_HOME/build-tools/34.0.0/aapt2"

    echo "🚀 Ghostty Android Development Environment (Nix-provisioned)"
    echo "============================================================"
    echo ""
    echo "✓ ANDROID_HOME: $ANDROID_HOME"
    echo "✓ ANDROID_NDK_ROOT: $ANDROID_NDK_ROOT"
    echo "✓ Java:    $(java -version 2>&1 | head -n 1)"
    echo "✓ ADB:     $(adb --version | head -n 1)"
    echo ""
    echo "Note: Android SDK/NDK fully provided by Nix!"
    echo "Note: Zig 0.15.2 will be provided by Ghostty's nix-shell during builds"
    echo ""
    echo "Build commands:"
    echo "  make help          - Show all available targets"
    echo "  make setup         - Clone Ghostty and setup submodules"
    echo "  make build-native  - Build libghostty for all Android targets"
    echo "  make clean         - Clean build artifacts"
    echo ""
  '';

  # Environment variables for Android builds
  ANDROID_TARGET_API = "34";
  ANDROID_MIN_API = "24";

  # Supported Android ABIs
  ANDROID_ABIS = "arm64-v8a armeabi-v7a x86_64";
}
