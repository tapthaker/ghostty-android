# Ghostty Android - Makefile
# Build system for cross-compiling libghostty-vt to Android targets

.PHONY: help setup build-native build-android android android-studio clean clean-all check-env check-nix-shell test test-list test-feedback test-feedback-list test-feedback-id test-feedback-from

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
COLOR_RED = \033[31m

## check-nix-shell: Verify we're running inside nix-shell (internal)
check-nix-shell:
	@if [ -z "$(IN_NIX_SHELL)" ] && [ -z "$(ANDROID_HOME)" ]; then \
		echo ""; \
		echo -e "$(COLOR_RED)╔══════════════════════════════════════════════════════════════╗$(COLOR_RESET)"; \
		echo -e "$(COLOR_RED)║  ERROR: Not running inside nix-shell                        ║$(COLOR_RESET)"; \
		echo -e "$(COLOR_RED)╚══════════════════════════════════════════════════════════════╝$(COLOR_RESET)"; \
		echo ""; \
		echo -e "$(COLOR_YELLOW)All build commands must be run within nix-shell.$(COLOR_RESET)"; \
		echo ""; \
		echo -e "$(COLOR_BOLD)To enter nix-shell, run:$(COLOR_RESET)"; \
		echo "  $$ nix-shell"; \
		echo ""; \
		echo -e "$(COLOR_BOLD)Then run your make command:$(COLOR_RESET)"; \
		echo "  [nix-shell] $$ make $(filter-out check-nix-shell,$(MAKECMDGOALS))"; \
		echo ""; \
		exit 1; \
	fi

## help: Show this help message
help:
	@echo -e "$(COLOR_BOLD)Ghostty Android Build System$(COLOR_RESET)"
	@echo ""
	@echo -e "$(COLOR_YELLOW)⚠️  IMPORTANT: All commands must be run inside nix-shell$(COLOR_RESET)"
	@echo -e "$(COLOR_YELLOW)   First run: nix-shell$(COLOR_RESET)"
	@echo ""
	@echo -e "$(COLOR_GREEN)Available targets:$(COLOR_RESET)"
	@echo -e "  $(COLOR_BOLD)make android-studio$(COLOR_RESET) - Open Android Studio (NixOS recommended method)"
	@echo -e "  $(COLOR_BOLD)make android$(COLOR_RESET)        - Build everything and install to device"
	@echo -e "  $(COLOR_BOLD)make setup$(COLOR_RESET)          - Clone Ghostty submodule and setup project"
	@echo -e "  $(COLOR_BOLD)make check-env$(COLOR_RESET)      - Check required environment variables"
	@echo -e "  $(COLOR_BOLD)make build-native$(COLOR_RESET)   - Build libghostty-vt + renderer for all Android ABIs"
	@echo -e "  $(COLOR_BOLD)make build-android$(COLOR_RESET)  - Build the Android app (after build-native)"
	@echo -e "  $(COLOR_BOLD)make install$(COLOR_RESET)        - Install APK to connected device"
	@echo -e "  $(COLOR_BOLD)make logs$(COLOR_RESET)           - Show filtered adb logs for Ghostty app"
	@echo ""
	@echo -e "$(COLOR_GREEN)Testing:$(COLOR_RESET)"
	@echo -e "  $(COLOR_BOLD)make test-feedback$(COLOR_RESET)      - Run all feedback loop tests (interactive)"
	@echo -e "  $(COLOR_BOLD)make test-feedback-list$(COLOR_RESET) - List all available test IDs"
	@echo -e "  $(COLOR_BOLD)make test-feedback-id$(COLOR_RESET)   - Run specific test (e.g., TEST_ID=text_attributes)"
	@echo -e "  $(COLOR_BOLD)make test-feedback-from$(COLOR_RESET) - Run tests starting from ID (e.g., FROM=256_colors)"
	@echo ""
	@echo -e "$(COLOR_GREEN)Maintenance:$(COLOR_RESET)"
	@echo -e "  $(COLOR_BOLD)make clean$(COLOR_RESET)          - Clean build artifacts"
	@echo -e "  $(COLOR_BOLD)make clean-all$(COLOR_RESET)      - Clean everything including Ghostty"
	@echo ""
	@echo -e "$(COLOR_YELLOW)Configuration:$(COLOR_RESET)"
	@echo "  ANDROID_HOME:       $(ANDROID_HOME)"
	@echo "  ANDROID_NDK_ROOT:   $(ANDROID_NDK_ROOT)"
	@echo "  ANDROID_TARGET_API: $(ANDROID_TARGET_API)"
	@echo "  ANDROID_MIN_API:    $(ANDROID_MIN_API)"
	@echo "  ANDROID_ABIS:       $(ANDROID_ABIS)"

## check-env: Verify environment variables are set
check-env: check-nix-shell
	@echo -e "$(COLOR_BLUE)Checking environment...$(COLOR_RESET)"
	@if [ -z "$(ANDROID_HOME)" ]; then \
		echo -e "$(COLOR_YELLOW)⚠️  ANDROID_HOME not set$(COLOR_RESET)"; \
		exit 1; \
	fi
	@if [ -z "$(ANDROID_NDK_ROOT)" ]; then \
		echo -e "$(COLOR_YELLOW)⚠️  ANDROID_NDK_ROOT not set$(COLOR_RESET)"; \
		exit 1; \
	fi
	@echo -e "$(COLOR_GREEN)✓ Environment configured correctly$(COLOR_RESET)"
	@echo "  Note: Zig 0.15.2 will be provided by Ghostty's nix-shell during builds"

## setup: Initialize Ghostty submodule
setup: check-nix-shell
	@echo -e "$(COLOR_BLUE)Setting up Ghostty submodule...$(COLOR_RESET)"
	@if [ ! -d "$(GHOSTTY_DIR)/.git" ]; then \
		echo -e "$(COLOR_YELLOW)Cloning Ghostty repository...$(COLOR_RESET)"; \
		git submodule add $(GHOSTTY_REPO) $(GHOSTTY_DIR) || \
		(git submodule init && git submodule update); \
	else \
		echo -e "$(COLOR_GREEN)✓ Ghostty already cloned$(COLOR_RESET)"; \
		git submodule update --init --recursive; \
	fi
	@echo -e "$(COLOR_GREEN)✓ Setup complete$(COLOR_RESET)"

## build-native: Build libghostty-vt and renderer for Android targets
build-native: check-env setup
	@echo -e "$(COLOR_BLUE)Building libghostty-vt and renderer for Android...$(COLOR_RESET)"
	@mkdir -p $(BUILD_DIR)
	@for abi in $(ANDROID_ABIS); do \
		echo ""; \
		echo -e "$(COLOR_BOLD)Building for $$abi...$(COLOR_RESET)"; \
		$(MAKE) build-abi ABI=$$abi; \
	done
	@echo ""
	@echo -e "$(COLOR_GREEN)✓ All Android targets built successfully$(COLOR_RESET)"
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
android-studio: check-nix-shell build-native
	@echo -e "$(COLOR_BLUE)Opening Android Studio...$(COLOR_RESET)"
	@./scripts/build-with-studio.sh

## build-android: Build Android APK
build-android: check-nix-shell
	@echo -e "$(COLOR_BLUE)Building Android app...$(COLOR_RESET)"
	@if [ ! -d "android/app" ]; then \
		echo -e "$(COLOR_YELLOW)⚠️  Android project not initialized yet$(COLOR_RESET)"; \
		exit 1; \
	fi
	@./android/scripts/build-android.sh
	@echo -e "$(COLOR_GREEN)✓ Android APK built$(COLOR_RESET)"
	@echo "APK location: android/app/build/outputs/apk/debug/app-debug.apk"

## android: Build native libraries, Android APK, install to device, and launch (one-stop command)
android: check-nix-shell
	@./android/scripts/build-android.sh --install
	@echo -e "$(COLOR_YELLOW)Launching Ghostty...$(COLOR_RESET)"
	@adb shell am start -n com.ghostty.android/.MainActivity
	@echo ""
	@echo -e "$(COLOR_GREEN)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(COLOR_RESET)"
	@echo -e "$(COLOR_GREEN)✓ Ghostty Android built, installed, and launched successfully!$(COLOR_RESET)"
	@echo -e "$(COLOR_GREEN)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(COLOR_RESET)"
	@echo ""
	@echo -e "$(COLOR_BOLD)Native Libraries:$(COLOR_RESET)"
	@ls -lh $(ANDROID_LIBS_DIR)/*/*.so 2>/dev/null || echo "  (none found)"
	@echo ""
	@echo -e "$(COLOR_BOLD)APK Location:$(COLOR_RESET)"
	@echo "  android/app/build/outputs/apk/debug/app-debug.apk"
	@echo ""
	@echo -e "$(COLOR_YELLOW)Run 'adb logcat | grep -E \"(GhosttyBridge|TerminalSession)\"' to view logs$(COLOR_RESET)"
	@echo ""

## install: Install app to connected device
install: check-nix-shell build-android
	@echo -e "$(COLOR_BLUE)Installing to device...$(COLOR_RESET)"
	cd android && ./gradlew installDebug
	@echo -e "$(COLOR_GREEN)✓ App installed$(COLOR_RESET)"

## logs: Show filtered adb logs for Ghostty app package
logs: check-nix-shell
	@echo -e "$(COLOR_BLUE)Showing logs for com.ghostty.android...$(COLOR_RESET)"
	@echo -e "$(COLOR_YELLOW)Press Ctrl+C to stop$(COLOR_RESET)"
	@adb logcat --pid=$$(adb shell pidof -s com.ghostty.android) 2>/dev/null || \
		(echo -e "$(COLOR_YELLOW)App not running, showing all logs with package filter...$(COLOR_RESET)" && \
		adb logcat | grep --line-buffered "com.ghostty.android")

## test-feedback: Run all feedback loop tests (interactive)
test-feedback: check-nix-shell
	@echo -e "$(COLOR_BLUE)Running feedback loop tests (interactive)...$(COLOR_RESET)"
	@echo -e "$(COLOR_YELLOW)Note: This will launch tests one at a time for manual verification$(COLOR_RESET)"
	@python3 test_feedback_loop.py

## test-feedback-list: List all available test IDs
test-feedback-list:
	@echo -e "$(COLOR_BOLD)Available Test IDs:$(COLOR_RESET)"
	@echo ""
	@echo -e "$(COLOR_GREEN)Basic Colors:$(COLOR_RESET)"
	@echo "  - basic_colors_fg"
	@echo "  - basic_colors_bg"
	@echo "  - 256_colors"
	@echo "  - rgb_colors"
	@echo ""
	@echo -e "$(COLOR_GREEN)Text Attributes:$(COLOR_RESET)"
	@echo "  - text_attributes"
	@echo "  - combined_attributes"
	@echo ""
	@echo -e "$(COLOR_GREEN)Cursor & Movement:$(COLOR_RESET)"
	@echo "  - cursor_position"
	@echo "  - cursor_movement"
	@echo ""
	@echo -e "$(COLOR_GREEN)Screen Operations:$(COLOR_RESET)"
	@echo "  - screen_clear"
	@echo "  - line_operations"
	@echo "  - scrollback"
	@echo ""
	@echo -e "$(COLOR_GREEN)Line Wrapping:$(COLOR_RESET)"
	@echo "  - line_wrap_basic"
	@echo "  - line_wrap_word_boundary"
	@echo "  - line_wrap_ansi_colors"
	@echo ""
	@echo -e "$(COLOR_GREEN)Unicode & Special Characters:$(COLOR_RESET)"
	@echo "  - utf8_basic"
	@echo "  - emoji"
	@echo "  - box_drawing"
	@echo "  - special_chars"
	@echo "  - double_width"
	@echo "  - combining_chars"
	@echo ""
	@echo -e "$(COLOR_YELLOW)Usage:$(COLOR_RESET)"
	@echo "  make test-feedback-id TEST_ID=text_attributes"
	@echo "  make test-feedback-from FROM=256_colors"

## test-feedback-id: Run a specific test by ID
test-feedback-id: check-nix-shell
	@if [ -z "$(TEST_ID)" ]; then \
		echo -e "$(COLOR_YELLOW)Error: TEST_ID not specified$(COLOR_RESET)"; \
		echo "Usage: make test-feedback-id TEST_ID=text_attributes"; \
		echo ""; \
		echo "Run 'make test-feedback-list' to see all available test IDs"; \
		exit 1; \
	fi
	@echo -e "$(COLOR_BLUE)Running test: $(TEST_ID)$(COLOR_RESET)"
	@python3 test_feedback_loop.py --test-id $(TEST_ID)

## test-feedback-from: Run tests starting from a specific test ID
test-feedback-from: check-nix-shell
	@if [ -z "$(FROM)" ]; then \
		echo -e "$(COLOR_YELLOW)Error: FROM not specified$(COLOR_RESET)"; \
		echo "Usage: make test-feedback-from FROM=256_colors"; \
		echo ""; \
		echo "Run 'make test-feedback-list' to see all available test IDs"; \
		exit 1; \
	fi
	@echo -e "$(COLOR_BLUE)Running tests starting from: $(FROM)$(COLOR_RESET)"
	@python3 test_feedback_loop.py --start-from $(FROM)

## test: Alias for test-feedback (for convenience)
test: test-feedback

## test-list: Alias for test-feedback-list (for convenience)
test-list: test-feedback-list

## clean: Clean build artifacts
clean:
	@echo -e "$(COLOR_BLUE)Cleaning build artifacts...$(COLOR_RESET)"
	rm -rf $(BUILD_DIR)
	rm -rf $(ANDROID_LIBS_DIR)
	@if [ -d "android" ]; then \
		cd android && ./gradlew clean 2>/dev/null || true; \
	fi
	@if [ -d "$(GHOSTTY_DIR)/zig-out" ]; then \
		rm -rf $(GHOSTTY_DIR)/zig-out; \
	fi
	@echo -e "$(COLOR_GREEN)✓ Clean complete$(COLOR_RESET)"

## clean-all: Clean everything including Ghostty
clean-all: clean
	@echo -e "$(COLOR_BLUE)Removing Ghostty submodule...$(COLOR_RESET)"
	@if [ -d "$(GHOSTTY_DIR)" ]; then \
		git submodule deinit -f $(GHOSTTY_DIR); \
		rm -rf $(GHOSTTY_DIR); \
		git rm -f $(GHOSTTY_DIR) 2>/dev/null || true; \
	fi
	@echo -e "$(COLOR_GREEN)✓ Full clean complete$(COLOR_RESET)"

## test-zig: Test Zig compilation without Android
test-zig:
	@echo -e "$(COLOR_BLUE)Testing Zig build...$(COLOR_RESET)"
	@if [ -d "$(GHOSTTY_DIR)" ]; then \
		cd $(GHOSTTY_DIR) && nix-shell --run "zig build lib-vt -Doptimize=ReleaseFast"; \
		echo -e "$(COLOR_GREEN)✓ Zig build test passed$(COLOR_RESET)"; \
	else \
		echo -e "$(COLOR_YELLOW)⚠️  Run 'make setup' first$(COLOR_RESET)"; \
	fi

## info: Show build information
info:
	@echo -e "$(COLOR_BOLD)Build Information$(COLOR_RESET)"
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
