package com.ghostty.android.testing

/**
 * Collection of visual regression tests for Ghostty Android.
 *
 * This suite contains tests for rendering ANSI escape sequences,
 * colors, cursor positioning, text attributes, and more.
 */
object TestSuite {

    /**
     * All available test cases.
     */
    fun getAllTests(): List<TestCase> = listOf(
        // Basic color tests
        *getColorTests().toTypedArray(),

        // Text attribute tests
        *getAttributeTests().toTypedArray(),

        // Cursor movement tests
        *getCursorTests().toTypedArray(),

        // Screen control tests
        *getScreenTests().toTypedArray(),

        // Line wrapping tests
        *getWrapTests().toTypedArray(),

        // Character set tests
        *getCharsetTests().toTypedArray(),

        // Replay tests (from real terminal sessions)
        *getReplayTests().toTypedArray()
    )

    /**
     * Basic ANSI color tests (16 colors, 256 colors, RGB).
     */
    fun getColorTests(): List<TestCase> = listOf(
        testCase("basic_colors_fg", "Basic 16 foreground colors") {
            tags("color", "ansi", "basic")
            ansi("\u001B[2J\u001B[H")  // Clear screen, move cursor to home
            ansi("Default color\n")
            ansi("\u001B[30mBlack\n")
            ansi("\u001B[31mRed\n")
            ansi("\u001B[32mGreen\n")
            ansi("\u001B[33mYellow\n")
            ansi("\u001B[34mBlue\n")
            ansi("\u001B[35mMagenta\n")
            ansi("\u001B[36mCyan\n")
            ansi("\u001B[37mWhite\n")
            ansi("\u001B[90mBright Black\n")
            ansi("\u001B[91mBright Red\n")
            ansi("\u001B[92mBright Green\n")
            ansi("\u001B[93mBright Yellow\n")
            ansi("\u001B[94mBright Blue\n")
            ansi("\u001B[95mBright Magenta\n")
            ansi("\u001B[96mBright Cyan\n")
            ansi("\u001B[97mBright White\n")
            ansi("\u001B[0m")  // Reset
        },

        testCase("basic_colors_bg", "Basic 16 background colors") {
            tags("color", "ansi", "basic")
            ansi("\u001B[2J\u001B[H")  // Clear screen
            ansi("Background Colors:\n")
            ansi("\u001B[40m Black BG \u001B[0m\n")
            ansi("\u001B[41m Red BG   \u001B[0m\n")
            ansi("\u001B[42m Green BG \u001B[0m\n")
            ansi("\u001B[43m Yellow BG\u001B[0m\n")
            ansi("\u001B[44m Blue BG  \u001B[0m\n")
            ansi("\u001B[45m Magenta  \u001B[0m\n")
            ansi("\u001B[46m Cyan BG  \u001B[0m\n")
            ansi("\u001B[47m White BG \u001B[0m\n")
        },

        testCase("256_colors", "256 color palette") {
            tags("color", "256color")
            ansi("\u001B[2J\u001B[H")  // Clear screen
            ansi("256 Color Palette:\n")
            // Show a sample of 256 colors
            for (i in 0..15) {
                ansi("\u001B[38;5;${i}m█")
            }
            ansi("\u001B[0m\n")
            for (row in 0..5) {
                for (col in 0..35) {
                    val color = 16 + row * 36 + col
                    if (color < 256) {
                        ansi("\u001B[38;5;${color}m█")
                    }
                }
                ansi("\u001B[0m\n")
            }
        },

        testCase("rgb_colors", "True color (24-bit RGB)") {
            tags("color", "truecolor", "rgb")
            ansi("\u001B[2J\u001B[H")  // Clear screen
            ansi("RGB Gradient:\n")
            // Red gradient
            for (i in 0..15) {
                val r = (i * 255 / 15)
                ansi("\u001B[38;2;${r};0;0m█")
            }
            ansi("\u001B[0m\n")
            // Green gradient
            for (i in 0..15) {
                val g = (i * 255 / 15)
                ansi("\u001B[38;2;0;${g};0m█")
            }
            ansi("\u001B[0m\n")
            // Blue gradient
            for (i in 0..15) {
                val b = (i * 255 / 15)
                ansi("\u001B[38;2;0;0;${b}m█")
            }
            ansi("\u001B[0m\n")
        }
    )

    /**
     * Text attribute tests (bold, italic, underline, etc.).
     */
    fun getAttributeTests(): List<TestCase> = listOf(
        testCase("text_attributes", "Text styling attributes") {
            tags("attributes", "style")
            ansi("\u001B[2J\u001B[H")  // Clear screen
            ansi("Text Attributes:\n")
            ansi("Normal text\n")
            ansi("\u001B[1mBold text\u001B[0m\n")
            ansi("\u001B[2mDim text\u001B[0m\n")
            ansi("\u001B[3mItalic text\u001B[0m\n")
            ansi("\u001B[4mUnderlined text\u001B[0m\n")
            ansi("\u001B[7mReverse video\u001B[0m\n")
            ansi("\u001B[9mStrikethrough\u001B[0m\n")
        },

        testCase("combined_attributes", "Combined text attributes") {
            tags("attributes", "style", "combined")
            ansi("\u001B[2J\u001B[H")  // Clear screen
            ansi("Combined Attributes:\n")
            ansi("\u001B[1;31mBold Red\u001B[0m\n")
            ansi("\u001B[4;32mUnderlined Green\u001B[0m\n")
            ansi("\u001B[1;4;33mBold Underlined Yellow\u001B[0m\n")
            ansi("\u001B[7;35mReverse Magenta\u001B[0m\n")
        },

        testCase("inverse_space_cursor", "Inverse video on space (terminal cursor)") {
            tags("attributes", "cursor", "inverse", "regression")
            ansi("\u001B[2J\u001B[H")  // Clear screen
            ansi("Inverse Space Cursor Test:\n\n")
            ansi("This tests that a SPACE with reverse video renders as a block.\n")
            ansi("Used by terminals to render the cursor position.\n\n")
            ansi("Cursor after text: ")
            ansi("Hello\u001B[7m \u001B[27m")  // SGR 7 = inverse, space, SGR 27 = reset inverse
            ansi("\n\n")
            ansi("Cursor at start: ")
            ansi("\u001B[7m \u001B[27m")  // Just the inverse space
            ansi("World\n\n")
            ansi("Multiple cursor positions:\n")
            ansi("A\u001B[7m \u001B[27mB\u001B[7m \u001B[27mC\u001B[7m \u001B[27m\n\n")
            ansi("If you see solid blocks after text, inverse space works correctly.")
        }
    )

    /**
     * Cursor movement and positioning tests.
     */
    fun getCursorTests(): List<TestCase> = listOf(
        testCase("cursor_position", "Cursor positioning") {
            tags("cursor", "movement")
            ansi("\u001B[2J\u001B[H")  // Clear screen, home
            ansi("Top left")
            ansi("\u001B[10;20H")  // Move to row 10, col 20
            ansi("Middle")
            ansi("\u001B[20;1H")  // Move to row 20, col 1
            ansi("Bottom")
        },

        testCase("cursor_movement", "Cursor movement sequences") {
            tags("cursor", "movement")
            ansi("\u001B[2J\u001B[H")  // Clear screen, home
            ansi("Start")
            ansi("\u001B[5B")  // Move down 5 lines
            ansi("Down 5")
            ansi("\u001B[3A")  // Move up 3 lines
            ansi(" Up 3")
            ansi("\u001B[10C")  // Move right 10 columns
            ansi("Right 10")
        },

        testCase("cursor_visibility", "Cursor show/hide (DECTCEM)") {
            tags("cursor", "visibility", "dectcem")
            ansi("\u001B[2J\u001B[H")  // Clear screen, home
            ansi("Cursor Visibility Test (DECTCEM Mode 25)\n\n")
            ansi("1. Cursor should be VISIBLE here:\n")
            ansi("\u001B[?25h")  // Ensure cursor is visible (ESC[?25h)
            ansi("\n")
            ansi("2. Now hiding cursor with ESC[?25l...\n")
            ansi("\u001B[?25l")  // Hide cursor (ESC[?25l)
            ansi("   Cursor should be HIDDEN now.\n\n")
            ansi("3. Restoring cursor with ESC[?25h...\n")
            ansi("\u001B[?25h")  // Show cursor again (ESC[?25h)
            ansi("   Cursor should be VISIBLE again:")
        },

        testCase("cursor_styles", "Cursor shapes (DECSCUSR)") {
            tags("cursor", "style", "decscusr")
            ansi("\u001B[2J\u001B[H")  // Clear screen, home
            ansi("Cursor Style Test (DECSCUSR)\n\n")
            ansi("Current style: UNDERLINE (ESC[4 q)\n\n")
            ansi("Try these sequences to change cursor style:\n")
            ansi("  ESC[1 q or ESC[2 q - Block\n")
            ansi("  ESC[3 q or ESC[4 q - Underline\n")
            ansi("  ESC[5 q or ESC[6 q - Bar\n\n")
            ansi("Cursor is here -->")
            ansi("\u001B[4 q")  // Set underline style to demonstrate
        },

        testCase("cursor_up_overwrite", "Cursor up with overwrite (ESC[A)") {
            tags("cursor", "movement", "cuu", "regression")
            ansi("\u001B[2J\u001B[H")  // Clear screen, home
            ansi("Cursor Up Overwrite Test (ESC[nA):\n\n")
            ansi("This tests that ESC[A moves cursor UP, not down.\n\n")
            // Write 5 labeled lines
            ansi("LINE 1: Original text\n")
            ansi("LINE 2: Original text\n")
            ansi("LINE 3: Original text\n")
            ansi("LINE 4: Original text\n")
            ansi("LINE 5: Original text\n")
            // Now cursor is on LINE 6 (after LINE 5)
            // Move up 3 lines (should land on LINE 3)
            ansi("\u001B[3A")
            // Overwrite from current position
            ansi("REPLACED")
            // Move down to show result
            ansi("\n\n")
            ansi("If cursor-up works, LINE 3 should read:\n")
            ansi("  'REPLACED Original text'\n\n")
            ansi("If you see 'REPLACED' below LINE 5,\n")
            ansi("then cursor-up is broken!")
        },

        testCase("cursor_up_erase_redraw", "Cursor up with erase (TUI pattern)") {
            tags("cursor", "movement", "erase", "tui", "regression")
            ansi("\u001B[2J\u001B[H")  // Clear screen, home
            ansi("TUI Redraw Pattern Test:\n\n")
            ansi("This simulates how TUI apps redraw screens.\n")
            ansi("Pattern: move up, erase line, write new content.\n\n")
            // Write initial content (5 lines)
            ansi("OLD LINE 1\n")
            ansi("OLD LINE 2\n")
            ansi("OLD LINE 3\n")
            ansi("OLD LINE 4\n")
            ansi("OLD LINE 5\n")
            // Cursor is now after LINE 5
            // Do the TUI redraw pattern: ESC[2K ESC[1A (erase line, move up)
            ansi("\u001B[2K\u001B[1A")  // Erase current (6), up to 5
            ansi("\u001B[2K\u001B[1A")  // Erase 5, up to 4
            ansi("\u001B[2K\u001B[1A")  // Erase 4, up to 3
            ansi("\u001B[2K\u001B[1A")  // Erase 3, up to 2
            ansi("\u001B[2K\u001B[1A")  // Erase 2, up to 1
            ansi("\u001B[2K")          // Erase 1
            ansi("\u001B[G")           // Column 1
            // Now write new content
            ansi("NEW LINE 1\n")
            ansi("NEW LINE 2\n")
            ansi("NEW LINE 3\n")
            ansi("NEW LINE 4\n")
            ansi("NEW LINE 5\n\n")
            ansi("If TUI pattern works correctly:\n")
            ansi("- You should see NEW LINE 1-5 above\n")
            ansi("- NO 'OLD LINE' text should be visible\n")
            ansi("- NO extra blank lines between content")
        }
    )

    /**
     * Screen control tests (clear, scroll, etc.).
     */
    fun getScreenTests(): List<TestCase> = listOf(
        testCase("screen_clear", "Screen clearing operations") {
            tags("screen", "clear")
            ansi("\u001B[2J\u001B[H")  // Clear entire screen
            ansi("Screen cleared\n")
            ansi("Line 2\n")
            ansi("Line 3\n")
        },

        testCase("line_operations", "Line operations") {
            tags("screen", "line")
            ansi("\u001B[2J\u001B[H")  // Clear screen
            ansi("First line\n")
            ansi("Second line")
            ansi("\u001B[2K")  // Clear entire line
            ansi("Line cleared and rewritten\n")
            ansi("Third line\n")
        }
    )

    /**
     * Line wrapping and reflow tests.
     */
    fun getWrapTests(): List<TestCase> = listOf(
        testCase("line_wrap_basic", "Basic line wrapping") {
            tags("wrap", "reflow")
            ansi("\u001B[2J\u001B[H")  // Clear screen
            ansi("Test line wrapping with a very long line that should wrap to the next line automatically when it reaches the terminal width boundary")
        },

        testCase("line_wrap_word_boundary", "Word boundary wrapping") {
            tags("wrap", "word")
            ansi("\u001B[2J\u001B[H")
            ansi("This is a test of word wrapping. ")
            ansi("It should handle spaces properly. ")
            ansi("VeryLongWordThatCannotBeBrokenUpAndMustWrapAtCharacterBoundary")
        },

        testCase("line_wrap_ansi_colors", "Wrapping with ANSI colors") {
            tags("wrap", "color")
            ansi("\u001B[2J\u001B[H")
            ansi("\u001B[31m")  // Red
            ansi("This is a very long red line that should wrap while maintaining its color across line boundaries ")
            ansi("\u001B[32m")  // Green
            ansi("and this green text should also wrap properly\u001B[0m")
        },

        testCase("scrollback", "Scrollback buffer test") {
            tags("wrap", "scroll")
            ansi("\u001B[2J\u001B[H")
            // Fill screen with numbered lines
            for (i in 1..30) {
                ansi("Line $i: This is test content for scrollback\n")
            }
        }
    )

    /**
     * Character set and special character tests.
     */
    fun getCharsetTests(): List<TestCase> = listOf(
        testCase("utf8_basic", "Basic UTF-8 characters") {
            tags("charset", "utf8")
            ansi("\u001B[2J\u001B[H")
            ansi("UTF-8 Test:\n")
            ansi("Latin: Hello Wörld\n")
            ansi("Greek: Γειά σου κόσμε\n")
            ansi("Cyrillic: Привет мир\n")
            ansi("CJK: 你好世界 こんにちは世界\n")
            ansi("Arabic: مرحبا بالعالم\n")
        },

        testCase("emoji", "Emoji rendering") {
            tags("charset", "emoji", "utf8")
            ansi("\u001B[2J\u001B[H")
            ansi("Emoji Test:\n")
            ansi("😀 😃 😄 😁 😆\n")
            ansi("❤️ 💙 💚 💛 💜\n")
            ansi("👍 👎 ✅ ❌ ⭐\n")
            ansi("🚀 🔥 💻 📱 🎮\n")
        },

        testCase("box_drawing", "Box drawing characters") {
            tags("charset", "box", "unicode")
            ansi("\u001B[2J\u001B[H")
            ansi("Box Drawing:\n")
            ansi("┌─────────┐\n")
            ansi("│ Content │\n")
            ansi("├─────────┤\n")
            ansi("│ Data    │\n")
            ansi("└─────────┘\n")
        },

        testCase("special_chars", "Special characters") {
            tags("charset", "special")
            ansi("\u001B[2J\u001B[H")
            ansi("Special Characters:\n")
            ansi("Tab:\t\ttest\n")
            ansi("Bell: \u0007\n")  // Bell character
            ansi("Null handling: before\u0000after\n")
            ansi("Backspace: abc\u0008\u0008DEF\n")
        },

        testCase("double_width", "Double-width characters") {
            tags("charset", "cjk", "width")
            ansi("\u001B[2J\u001B[H")
            ansi("Double-width test:\n")
            ansi("漢字 (Kanji)\n")
            ansi("한글 (Hangul)\n")
            ansi("中文 (Chinese)\n")
            ansi("Mix: A漢B字C\n")
        },

        testCase("combining_chars", "Combining characters") {
            tags("charset", "combining", "diacritics")
            ansi("\u001B[2J\u001B[H")
            ansi("Combining Characters:\n")
            ansi("é (e + ´)\n")
            ansi("ñ (n + ~)\n")
            ansi("ö (o + ¨)\n")
            ansi("å (a + ˚)\n")
        },

        testCase("prompt_symbols", "Prompt/UI symbols") {
            tags("charset", "symbols", "ui")
            ansi("\u001B[2J\u001B[H")
            ansi("Prompt/UI Symbols Test:\n\n")
            ansi("Return symbol: ↵\n")
            ansi("Forward slash: /\n")
            ansi("Play triangles: ⏵⏵\n")
            ansi("Combined prompt: ⏵⏵ user@host / ~/code ↵\n")
            ansi("\n")
            ansi("Additional arrows:\n")
            ansi("→ ← ↑ ↓ ↵ ↲ ⏎\n")
            ansi("\n")
            ansi("Additional triangles:\n")
            ansi("▶ ▷ ◀ ◁ ⏵ ⏴\n")
            ansi("\n")
            ansi("Common prompt chars:\n")
            ansi("$ % # > » › ❯ ➜\n")
        }
    )

    /**
     * Replay tests from real terminal sessions.
     *
     * These tests use actual captured terminal output to verify rendering
     * matches real-world usage patterns.
     */
    fun getReplayTests(): List<TestCase> = listOf(
        testCase("replay_sync_cursor_up", "Sync mode with cursor-up (Claude Code pattern)") {
            tags("replay", "sync", "cursor", "regression")
            // This is actual captured output from a Claude Code session
            // Pattern: sync start, cursor-up/erase, content, sync end
            //
            // This tests the TUI redraw pattern with synchronized output:
            // 1. ESC[?2026h - Start synchronized output mode
            // 2. ESC[2K ESC[1A - Erase line, move up (repeated)
            // 3. ESC[G - Move to column 1
            // 4. Write new content with CRLF
            // 5. ESC[?2026l - End synchronized output mode
            ansi("\u001B[2J\u001B[H")  // Clear screen first
            ansi("Line 1: OLD content\n")      // Line 1
            ansi("Line 2: OLD content\n")      // Line 2
            ansi("Line 3: OLD content\n")      // Line 3
            ansi("Line 4: OLD content\n")      // Line 4
            ansi("Line 5: OLD content\n")      // Line 5
            // Cursor is now at start of line 6
            // Now simulate the Claude Code TUI redraw
            ansi("\u001B[?2026h")  // Start sync
            // 5 cursor-ups to go from line 6 back to line 1
            ansi("\u001B[2K\u001B[1A")  // Erase line 6, up to 5
            ansi("\u001B[2K\u001B[1A")  // Erase line 5, up to 4
            ansi("\u001B[2K\u001B[1A")  // Erase line 4, up to 3
            ansi("\u001B[2K\u001B[1A")  // Erase line 3, up to 2
            ansi("\u001B[2K\u001B[1A")  // Erase line 2, up to 1
            ansi("\u001B[2K")           // Erase line 1
            ansi("\u001B[G")  // Column 1
            ansi("\r\n")
            ansi("\u001B[2m\u001B[38;2;136;136;136m─────────────────────────────────────────────────\u001B[39m\u001B[22m\r\n")
            ansi(">\r\n")
            ansi("\u001B[2m\u001B[38;2;136;136;136m─────────────────────────────────────────────────\u001B[39m\u001B[22m\r\n")
            ansi("  \u001B[38;2;175;135;255m⏵⏵ accept edits on\u001B[38;2;153;153;153m · \u001B[38;2;0;204;204m1 background task\u001B[39m\r\n")
            ansi("\u001B[?2026l")  // End sync
            ansi("\n\n")
            ansi("If working correctly:\n")
            ansi("- You should see horizontal lines and '>' prompt above\n")
            ansi("- NO 'OLD content' text should be visible\n")
            ansi("- No extra blank lines between dividers")
        },

        testCase("replay_rapid_cursor_up", "Rapid cursor-up sequences") {
            tags("replay", "cursor", "stress", "regression")
            // Simulates rapid cursor-up/erase sequences like a loading spinner
            ansi("\u001B[2J\u001B[H")  // Clear screen
            ansi("Rapid Cursor-Up Test:\n\n")
            ansi("This simulates rapid TUI updates.\n\n")
            // Write initial state (3 lines)
            ansi("Status: Starting...\n")       // Line 5
            ansi("Progress: [          ] 0%\n") // Line 6
            ansi("Message: Initializing\n")     // Line 7
            // Cursor now at line 8
            // Need 3 cursor-ups to go from line 8 back to line 5
            // Pattern: erase current, up, erase, up, erase, up, erase, column 1
            // Rapid updates - frame 1
            ansi("\u001B[?2026h")
            ansi("\u001B[2K\u001B[1A\u001B[2K\u001B[1A\u001B[2K\u001B[1A\u001B[2K\u001B[G")
            ansi("Status: Running...\r\n")
            ansi("Progress: [██        ] 20%\r\n")
            ansi("Message: Loading data\r\n")
            ansi("\u001B[?2026l")
            // Frame 2
            ansi("\u001B[?2026h")
            ansi("\u001B[2K\u001B[1A\u001B[2K\u001B[1A\u001B[2K\u001B[1A\u001B[2K\u001B[G")
            ansi("Status: Running...\r\n")
            ansi("Progress: [████      ] 40%\r\n")
            ansi("Message: Processing\r\n")
            ansi("\u001B[?2026l")
            // Frame 3
            ansi("\u001B[?2026h")
            ansi("\u001B[2K\u001B[1A\u001B[2K\u001B[1A\u001B[2K\u001B[1A\u001B[2K\u001B[G")
            ansi("Status: Running...\r\n")
            ansi("Progress: [██████    ] 60%\r\n")
            ansi("Message: Almost done\r\n")
            ansi("\u001B[?2026l")
            // Frame 4 (final)
            ansi("\u001B[?2026h")
            ansi("\u001B[2K\u001B[1A\u001B[2K\u001B[1A\u001B[2K\u001B[1A\u001B[2K\u001B[G")
            ansi("Status: Complete!\r\n")
            ansi("Progress: [██████████] 100%\r\n")
            ansi("Message: Done!\r\n")
            ansi("\u001B[?2026l")
            ansi("\n")
            ansi("Expected result:\n")
            ansi("- 'Status: Complete!'\n")
            ansi("- 'Progress: [██████████] 100%'\n")
            ansi("- 'Message: Done!'\n")
            ansi("- NO duplicate lines or blanks above")
        },

        testCase("replay_real_message_6", "Real Claude Code session (message 6)") {
            tags("replay", "real", "regression")
            // Exact capture from session dab597f8-d341-4aae-b39e-78589db53eff message 6
            // This is a real TUI frame update from Claude Code
            ansi("\u001B[2J\u001B[H")  // Clear first
            ansi("Real captured message from Claude Code:\n\n")
            // The actual captured message
            ansi("\u001B[?2026h\u001B[2K\u001B[1A\u001B[2K\u001B[1A\u001B[2K\u001B[1A\u001B[2K\u001B[1A\u001B[2K\u001B[1A\u001B[2K\u001B[G\r\n")
            ansi("\u001B[2m\u001B[38;2;136;136;136m─────────────────────────────────────────────────\u001B[39m\u001B[22m\r\n")
            ansi(">\r\n")
            ansi("\u001B[2m\u001B[38;2;136;136;136m─────────────────────────────────────────────────\u001B[39m\u001B[22m\r\n")
            ansi("  \u001B[38;2;175;135;255m⏵⏵ accept edits on\u001B[38;2;153;153;153m · \u001B[38;2;0;204;204m1 background task\u001B[39m\r\n")
            ansi("\u001B[?2026l")
        },

        // === ISOLATION TESTS ===
        // These tests isolate specific factors to find the root cause

        testCase("isolate_crlf_cursor_up", "Cursor-up with CRLF (no sync)") {
            tags("isolate", "crlf", "cursor", "regression")
            // Test if CRLF affects cursor-up behavior (NO sync mode)
            ansi("\u001B[2J\u001B[H")
            ansi("CRLF Cursor-Up Test (no sync mode):\r\n\r\n")
            ansi("OLD LINE 1\r\n")
            ansi("OLD LINE 2\r\n")
            ansi("OLD LINE 3\r\n")
            // Cursor is after LINE 3
            // Do erase + cursor-up pattern
            ansi("\u001B[2K\u001B[1A")  // Erase current, up to 3
            ansi("\u001B[2K\u001B[1A")  // Erase 3, up to 2
            ansi("\u001B[2K\u001B[1A")  // Erase 2, up to 1
            ansi("\u001B[2K")          // Erase 1
            ansi("\u001B[G")           // Column 1
            ansi("NEW LINE 1\r\n")
            ansi("NEW LINE 2\r\n")
            ansi("NEW LINE 3\r\n\r\n")
            ansi("If working: NEW LINE 1-3 visible, NO OLD LINE text")
        },

        testCase("isolate_sync_lf_cursor_up", "Cursor-up with sync + LF") {
            tags("isolate", "sync", "lf", "cursor", "regression")
            // Test sync mode with LF (not CRLF)
            ansi("\u001B[2J\u001B[H")
            ansi("Sync + LF Cursor-Up Test:\n\n")
            ansi("OLD LINE 1\n")
            ansi("OLD LINE 2\n")
            ansi("OLD LINE 3\n")
            // Start sync mode, then do cursor operations
            ansi("\u001B[?2026h")  // Start sync
            ansi("\u001B[2K\u001B[1A")
            ansi("\u001B[2K\u001B[1A")
            ansi("\u001B[2K\u001B[1A")
            ansi("\u001B[2K")
            ansi("\u001B[G")
            ansi("NEW LINE 1\n")
            ansi("NEW LINE 2\n")
            ansi("NEW LINE 3\n")
            ansi("\u001B[?2026l")  // End sync
            ansi("\n")
            ansi("If working: NEW LINE 1-3 visible, NO OLD LINE text")
        },

        testCase("isolate_sync_only", "Sync mode without cursor-up") {
            tags("isolate", "sync", "regression")
            // Test if sync mode itself causes issues
            ansi("\u001B[2J\u001B[H")
            ansi("Sync Mode Only Test:\n\n")
            ansi("Content before sync.\n\n")
            ansi("\u001B[?2026h")  // Start sync
            ansi("This is inside sync mode.\n")
            ansi("Line 2 inside sync.\n")
            ansi("Line 3 inside sync.\n")
            ansi("\u001B[?2026l")  // End sync
            ansi("\n")
            ansi("Content after sync.\n\n")
            ansi("All text should be visible in order.")
        },

        testCase("isolate_no_sync_no_crlf", "Cursor-up baseline (LF, no sync)") {
            tags("isolate", "baseline", "cursor", "regression")
            // Baseline test - should definitely work
            ansi("\u001B[2J\u001B[H")
            ansi("Baseline Cursor-Up Test (LF, no sync):\n\n")
            ansi("OLD LINE 1\n")
            ansi("OLD LINE 2\n")
            ansi("OLD LINE 3\n")
            ansi("\u001B[2K\u001B[1A")
            ansi("\u001B[2K\u001B[1A")
            ansi("\u001B[2K\u001B[1A")
            ansi("\u001B[2K")
            ansi("\u001B[G")
            ansi("NEW LINE 1\n")
            ansi("NEW LINE 2\n")
            ansi("NEW LINE 3\n\n")
            ansi("If working: NEW LINE 1-3 visible, NO OLD LINE text")
        },

        // === FULL SESSION REPLAY TESTS ===
        // These load real captured terminal sessions from assets

        testCase("replay_dab597_instant", "Full session replay (instant)") {
            tags("replay", "asset", "full", "regression")
            // Replay the full captured Claude Code session instantly
            // This tests if cursor-up works when all messages are processed at once
            replayAsset("replay/dab597.log", delayMs = 0)
        },

        testCase("replay_dab597_30ms", "Full session replay (30ms delay)") {
            tags("replay", "asset", "full", "streaming", "regression")
            // Replay with 30ms delay between messages (simulates ClaudeLink's 30ms buffer)
            // This tests if timing affects cursor-up behavior
            replayAsset("replay/dab597.log", delayMs = 30)
        }
    )

    /**
     * Get tests by tag.
     */
    fun getTestsByTag(tag: String): List<TestCase> {
        return getAllTests().filter { it.tags.contains(tag) }
    }

    /**
     * Get test by ID.
     */
    fun getTestById(id: String): TestCase? {
        return getAllTests().firstOrNull { it.id == id }
    }
}
