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
        *getCharsetTests().toTypedArray()
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
