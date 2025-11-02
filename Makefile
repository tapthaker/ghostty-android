# Ghostty Android - Makefile
# Build system for cross-compiling libghostty-vt to Android targets

.PHONY: help setup build-native build-android android android-studio clean clean-all check-env test test-list

# Configuration
GHOSTTY_REPO = https://github.com/ghostty-org/ghostty.git
GHOSTTY_DIR = libghostty-vt
BUILD_DIR = build
ANDROID_LIBS_DIR = android/app/src/main/jniLibs

# Android configuration
ANDROID_TARGET_API ?= 34
ANDROID_MIN_API ?= 24
ANDROID_ABIS ?= arm64-v8a armeabi-v7a x86_64

# Zig targets for Android
# arm64-v8a  -> aarch64-linux-android
# armeabi-v7a -> armv7a-linux-android
# x86_64     -> x86_64-linux-android
ZIG_TARGET_arm64-v8a = aarch64-linux-android
ZIG_TARGET_armeabi-v7a = armv7a-linux-androideabi
ZIG_TARGET_x86_64 = x86_64-linux-android

# Colors for output
COLOR_RESET = \033[0m
COLOR_BOLD = \033[1m
COLOR_GREEN = \033[32m
COLOR_YELLOW = \033[33m
COLOR_BLUE = \033[34m

## help: Show this help message
help:
	@echo "$(COLOR_BOLD)Ghostty Android Build System$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_GREEN)Available targets:$(COLOR_RESET)"
	@echo "  $(COLOR_BOLD)make android-studio$(COLOR_RESET) - Open Android Studio (NixOS recommended method)"
	@echo "  $(COLOR_BOLD)make android$(COLOR_RESET)        - Build everything and install to device"
	@echo "  $(COLOR_BOLD)make setup$(COLOR_RESET)          - Clone Ghostty submodule and setup project"
	@echo "  $(COLOR_BOLD)make check-env$(COLOR_RESET)      - Check required environment variables"
	@echo "  $(COLOR_BOLD)make build-native$(COLOR_RESET)   - Build libghostty-vt + renderer for all Android ABIs"
	@echo "  $(COLOR_BOLD)make build-android$(COLOR_RESET)  - Build the Android app (after build-native)"
	@echo "  $(COLOR_BOLD)make install$(COLOR_RESET)        - Install APK to connected device"
	@echo "  $(COLOR_BOLD)make logs$(COLOR_RESET)           - Show filtered adb logs for Ghostty app"
	@echo "  $(COLOR_BOLD)make test$(COLOR_RESET)           - Run visual regression tests"
	@echo "  $(COLOR_BOLD)make test-list$(COLOR_RESET)      - List all available tests"
	@echo "  $(COLOR_BOLD)make clean$(COLOR_RESET)          - Clean build artifacts"
	@echo "  $(COLOR_BOLD)make clean-all$(COLOR_RESET)      - Clean everything including Ghostty"
	@echo ""
	@echo "$(COLOR_YELLOW)Configuration:$(COLOR_RESET)"
	@echo "  ANDROID_HOME:       $(ANDROID_HOME)"
	@echo "  ANDROID_NDK_ROOT:   $(ANDROID_NDK_ROOT)"
	@echo "  ANDROID_TARGET_API: $(ANDROID_TARGET_API)"
	@echo "  ANDROID_MIN_API:    $(ANDROID_MIN_API)"
	@echo "  ANDROID_ABIS:       $(ANDROID_ABIS)"

## check-env: Verify environment variables are set
check-env:
	@echo "$(COLOR_BLUE)Checking environment...$(COLOR_RESET)"
	@if [ -z "$(ANDROID_HOME)" ]; then \
		echo "$(COLOR_YELLOW)⚠️  ANDROID_HOME not set$(COLOR_RESET)"; \
		exit 1; \
	fi
	@if [ -z "$(ANDROID_NDK_ROOT)" ]; then \
		echo "$(COLOR_YELLOW)⚠️  ANDROID_NDK_ROOT not set$(COLOR_RESET)"; \
		exit 1; \
	fi
	@echo "$(COLOR_GREEN)✓ Environment configured correctly$(COLOR_RESET)"
	@echo "  Note: Zig 0.15.2 will be provided by Ghostty's nix-shell during builds"

## setup: Initialize Ghostty submodule
setup:
	@echo "$(COLOR_BLUE)Setting up Ghostty submodule...$(COLOR_RESET)"
	@if [ ! -d "$(GHOSTTY_DIR)/.git" ]; then \
		echo "$(COLOR_YELLOW)Cloning Ghostty repository...$(COLOR_RESET)"; \
		git submodule add $(GHOSTTY_REPO) $(GHOSTTY_DIR) || \
		(git submodule init && git submodule update); \
	else \
		echo "$(COLOR_GREEN)✓ Ghostty already cloned$(COLOR_RESET)"; \
		git submodule update --init --recursive; \
	fi
	@echo "$(COLOR_GREEN)✓ Setup complete$(COLOR_RESET)"

## build-native: Build libghostty-vt and renderer for Android targets
build-native: check-env setup
	@echo "$(COLOR_BLUE)Building libghostty-vt and renderer for Android...$(COLOR_RESET)"
	@mkdir -p $(BUILD_DIR)
	@for abi in $(ANDROID_ABIS); do \
		echo ""; \
		echo "$(COLOR_BOLD)Building for $$abi...$(COLOR_RESET)"; \
		$(MAKE) build-abi ABI=$$abi; \
	done
	@echo ""
	@echo "$(COLOR_GREEN)✓ All Android targets built successfully$(COLOR_RESET)"
	@echo "Libraries are in: $(ANDROID_LIBS_DIR)/"

## build-abi: Build for specific ABI (internal target)
build-abi:
	@if [ -z "$(ABI)" ]; then \
		echo "Error: ABI not specified"; \
		exit 1; \
	fi
	@output_dir="$(ANDROID_LIBS_DIR)/$(ABI)"; \
	ANDROID_MIN_API=$(ANDROID_MIN_API) ANDROID_NDK_ROOT=$(ANDROID_NDK_ROOT) \
		./scripts/build-android-abi.sh $(ABI) $$output_dir

## android-studio: Open project in Android Studio (NixOS recommended)
android-studio: build-native
	@echo "$(COLOR_BLUE)Opening Android Studio...$(COLOR_RESET)"
	@./scripts/build-with-studio.sh

## build-android: Build Android APK
build-android:
	@echo "$(COLOR_BLUE)Building Android app...$(COLOR_RESET)"
	@if [ ! -d "android/app" ]; then \
		echo "$(COLOR_YELLOW)⚠️  Android project not initialized yet$(COLOR_RESET)"; \
		exit 1; \
	fi
	@./android/scripts/build-android.sh
	@echo "$(COLOR_GREEN)✓ Android APK built$(COLOR_RESET)"
	@echo "APK location: android/app/build/outputs/apk/debug/app-debug.apk"

## android: Build native libraries, Android APK, and install to device (one-stop command)
android:
	@./android/scripts/build-android.sh --install
	@echo ""
	@echo "$(COLOR_GREEN)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(COLOR_RESET)"
	@echo "$(COLOR_GREEN)✓ Ghostty Android built and installed successfully!$(COLOR_RESET)"
	@echo "$(COLOR_GREEN)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)Native Libraries:$(COLOR_RESET)"
	@ls -lh $(ANDROID_LIBS_DIR)/*/*.so 2>/dev/null || echo "  (none found)"
	@echo ""
	@echo "$(COLOR_BOLD)APK Location:$(COLOR_RESET)"
	@echo "  android/app/build/outputs/apk/debug/app-debug.apk"
	@echo ""
	@echo "$(COLOR_YELLOW)Run 'adb logcat | grep -E \"(GhosttyBridge|TerminalSession)\"' to view logs$(COLOR_RESET)"
	@echo ""

## install: Install app to connected device
install: build-android
	@echo "$(COLOR_BLUE)Installing to device...$(COLOR_RESET)"
	cd android && ./gradlew installDebug
	@echo "$(COLOR_GREEN)✓ App installed$(COLOR_RESET)"

## logs: Show filtered adb logs for Ghostty app package
logs:
	@echo "$(COLOR_BLUE)Showing logs for com.ghostty.android...$(COLOR_RESET)"
	@echo "$(COLOR_YELLOW)Press Ctrl+C to stop$(COLOR_RESET)"
	@adb logcat --pid=$$(adb shell pidof -s com.ghostty.android) 2>/dev/null || \
		(echo "$(COLOR_YELLOW)App not running, showing all logs with package filter...$(COLOR_RESET)" && \
		adb logcat | grep --line-buffered "com.ghostty.android")

## test: Run visual regression tests
test:
	@echo "$(COLOR_BLUE)Running visual regression tests...$(COLOR_RESET)"
	cd tests/visual && python3 run_tests.py

## test-list: List all available tests
test-list:
	@cd tests/visual && python3 run_tests.py --list

## clean: Clean build artifacts
clean:
	@echo "$(COLOR_BLUE)Cleaning build artifacts...$(COLOR_RESET)"
	rm -rf $(BUILD_DIR)
	rm -rf $(ANDROID_LIBS_DIR)
	@if [ -d "android" ]; then \
		cd android && ./gradlew clean 2>/dev/null || true; \
	fi
	@if [ -d "$(GHOSTTY_DIR)/zig-out" ]; then \
		rm -rf $(GHOSTTY_DIR)/zig-out; \
	fi
	@echo "$(COLOR_GREEN)✓ Clean complete$(COLOR_RESET)"

## clean-all: Clean everything including Ghostty
clean-all: clean
	@echo "$(COLOR_BLUE)Removing Ghostty submodule...$(COLOR_RESET)"
	@if [ -d "$(GHOSTTY_DIR)" ]; then \
		git submodule deinit -f $(GHOSTTY_DIR); \
		rm -rf $(GHOSTTY_DIR); \
		git rm -f $(GHOSTTY_DIR) 2>/dev/null || true; \
	fi
	@echo "$(COLOR_GREEN)✓ Full clean complete$(COLOR_RESET)"

## test-zig: Test Zig compilation without Android
test-zig:
	@echo "$(COLOR_BLUE)Testing Zig build...$(COLOR_RESET)"
	@if [ -d "$(GHOSTTY_DIR)" ]; then \
		cd $(GHOSTTY_DIR) && nix-shell --run "zig build lib-vt -Doptimize=ReleaseFast"; \
		echo "$(COLOR_GREEN)✓ Zig build test passed$(COLOR_RESET)"; \
	else \
		echo "$(COLOR_YELLOW)⚠️  Run 'make setup' first$(COLOR_RESET)"; \
	fi

## info: Show build information
info:
	@echo "$(COLOR_BOLD)Build Information$(COLOR_RESET)"
	@echo ""
	@echo "Project: Ghostty Android"
	@echo "Build directory: $(BUILD_DIR)"
	@echo "Output directory: $(ANDROID_LIBS_DIR)"
	@echo ""
	@echo "Zig targets:"
	@for abi in $(ANDROID_ABIS); do \
		zig_target=$$(echo "$(ZIG_TARGET_$$abi)"); \
		echo "  $$abi -> $$zig_target"; \
	done
