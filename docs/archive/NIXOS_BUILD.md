# Building on NixOS

## ✅ AAPT2 Issue SOLVED!

The project now uses **Nix-provisioned Android SDK/NDK**, which automatically solves the AAPT2 dynamic linking issue on NixOS!

## What Changed

The `shell.nix` file now:
1. Provisions the complete Android SDK and NDK via `androidenv.composeAndroidPackages`
2. Sets `GRADLE_OPTS` to override AAPT2 with the Nix-provided binary
3. Requires **no manual Android SDK installation**

## Building the Project

Simply run:

```bash
# Enter the Nix shell (automatically downloads and configures Android SDK/NDK)
nix-shell

# Build native libraries for all Android ABIs
make build-native

# Build the Android APK
cd android
./gradlew assembleDebug
```

The APK will be at: `android/app/build/outputs/apk/debug/app-debug.apk`

## First-Time Setup

On first run, Nix will download approximately **350 MB** of Android SDK/NDK components from the Nix cache. This is a one-time operation and will be cached for future use.

## Benefits of Nix-Provisioned Android SDK

- ✅ Works perfectly on NixOS (no FHS compatibility issues)
- ✅ Fully reproducible builds
- ✅ No manual SDK installation
- ✅ Version-locked dependencies
- ✅ Automatic AAPT2 configuration
- ✅ Works the same way on all systems (NixOS, Linux, macOS)

## Project Status

✅ **Nix environment fully configured**
✅ **Android SDK/NDK automatically provisioned**
✅ **NixOS AAPT2 issue resolved**
✅ **Ready to build on any system**

## Additional Information

For detailed build system documentation, see [BUILD_SETUP.md](BUILD_SETUP.md).

## Related Links

- [NixOS Android Development](https://nixos.wiki/wiki/Android)
- [Nixpkgs androidenv Documentation](https://nixos.org/manual/nixpkgs/stable/#android)
