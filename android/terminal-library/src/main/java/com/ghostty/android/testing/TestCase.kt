package com.ghostty.android.testing

/**
 * Visual regression test case for Ghostty Android.
 *
 * Each test case contains ANSI escape sequences to render and
 * expected visual output for comparison.
 */
data class TestCase(
    /** Unique test identifier (e.g., "vttest_launch") */
    val id: String,

    /** Human-readable description */
    val description: String,

    /** Raw ANSI escape sequences to inject into the terminal */
    val ansiSequence: String,

    /** Optional: Expected terminal size (cols x rows) */
    val terminalSize: Pair<Int, Int> = Pair(80, 24),

    /** Optional: Reference image asset path for visual comparison */
    val referenceImage: String? = null,

    /** Optional: Tags for categorization (e.g., "color", "cursor", "vttest") */
    val tags: List<String> = emptyList(),

    /** Optional: Asset path for replay tests (base64-encoded messages, one per line) */
    val replayAssetPath: String? = null,

    /** Optional: Delay between replay messages in ms (0 = instant) */
    val replayDelayMs: Long = 0
) {
    /** Check if this is a replay test */
    val isReplayTest: Boolean get() = replayAssetPath != null

    override fun toString(): String = "TestCase($id: $description)"
}

/**
 * Builder for creating test cases with a fluent API.
 */
class TestCaseBuilder(
    private val id: String,
    private val description: String
) {
    private val sequences = mutableListOf<String>()
    private var termSize: Pair<Int, Int> = Pair(80, 24)
    private var refImage: String? = null
    private val testTags = mutableListOf<String>()
    private var assetPath: String? = null
    private var delayMs: Long = 0

    fun ansi(sequence: String): TestCaseBuilder {
        sequences.add(sequence)
        return this
    }

    fun terminalSize(cols: Int, rows: Int): TestCaseBuilder {
        termSize = Pair(cols, rows)
        return this
    }

    fun referenceImage(path: String): TestCaseBuilder {
        refImage = path
        return this
    }

    fun tags(vararg tags: String): TestCaseBuilder {
        testTags.addAll(tags)
        return this
    }

    /** Set asset path for replay test */
    fun replayAsset(path: String, delayMs: Long = 0): TestCaseBuilder {
        assetPath = path
        this.delayMs = delayMs
        return this
    }

    fun build(): TestCase = TestCase(
        id = id,
        description = description,
        ansiSequence = sequences.joinToString(""),
        terminalSize = termSize,
        referenceImage = refImage,
        tags = testTags,
        replayAssetPath = assetPath,
        replayDelayMs = delayMs
    )
}

/**
 * Helper function to create test cases.
 */
fun testCase(id: String, description: String, builder: TestCaseBuilder.() -> Unit): TestCase {
    return TestCaseBuilder(id, description).apply(builder).build()
}
