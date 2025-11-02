{ pkgs ? import <nixpkgs> {}, run ? null }:

# FHS environment that can run generic Linux binaries (like Android SDK tools, AAPT2, etc.)
# This is necessary on NixOS to run the Android toolchain which expects a traditional Linux filesystem
(pkgs.buildFHSUserEnv {
  name = "android-build-env";

  targetPkgs = pkgs: with pkgs; [
    # Build essentials
    gcc
    pkg-config
    zlib
    ncurses5
    stdenv.cc.cc.lib

    # Java for Gradle
    openjdk17

    # Build tools
    gnumake
    git
  ];

  multiPkgs = pkgs: with pkgs; [
    # 32-bit support for some Android tools
    zlib
  ];

  profile = ''
    export ANDROID_HOME=~/Android/Sdk
    export ANDROID_SDK_ROOT=$ANDROID_HOME
    export ANDROID_NDK_ROOT=~/Android/Sdk/ndk/29.0.14206865
    export JAVA_HOME=${pkgs.openjdk17}
  '';

  # Support --argstr run "command" workaround for buildFHSUserEnv
  runScript = if run != null then "bash -c ${pkgs.lib.escapeShellArg run}" else "bash";
}).env
