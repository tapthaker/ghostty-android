package com.ghostty.android.testing

import android.content.Context
import android.graphics.Bitmap
import android.os.Environment
import android.util.Log
import android.view.View
import com.ghostty.android.renderer.GhosttyRenderer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream

/**
 * Test runner for executing visual regression tests.
 *
 * This runner executes test cases by injecting ANSI sequences directly
 * into the renderer's terminal manager and capturing the rendered output.
 */
class TestRunner(
    private val renderer: GhosttyRenderer,
    private val context: Context,
    private val surfaceView: View? = null
) {
    private val scope = CoroutineScope(Dispatchers.Main + Job())
    private val screenshotDir = File(context.getExternalFilesDir(null), "test_screenshots")
        .apply { mkdirs() }

    private val _currentTest = MutableStateFlow<TestCase?>(null)
    val currentTest: StateFlow<TestCase?> = _currentTest.asStateFlow()

    private val _testResults = MutableStateFlow<List<TestResult>>(emptyList())
    val testResults: StateFlow<List<TestResult>> = _testResults.asStateFlow()

    private val _isRunning = MutableStateFlow(false)
    val isRunning: StateFlow<Boolean> = _isRunning.asStateFlow()

    // Test navigation state
    private var allTests = listOf<TestCase>()
    private var currentTestIndex = 0

    private val _currentTestIndex = MutableStateFlow(0)
    val currentTestIndexFlow: StateFlow<Int> = _currentTestIndex.asStateFlow()

    private val _totalTests = MutableStateFlow(0)
    val totalTests: StateFlow<Int> = _totalTests.asStateFlow()

    /**
     * Run a single test case.
     *
     * @param testCase The test to execute
     * @return The test result
     */
    suspend fun runTest(testCase: TestCase): TestResult {
        Log.i(TAG, "TEST_START:${testCase.id}")
        _currentTest.value = testCase

        val startTime = System.currentTimeMillis()

        return try {
            // Clear the terminal first
            renderer.processInput("\u001B[2J\u001B[H")

            // Inject the ANSI sequence immediately
            renderer.processInput(testCase.ansiSequence)

            Log.i(TAG, "TEST_READY:${testCase.id}")

            val endTime = System.currentTimeMillis()
            val duration = endTime - startTime

            Log.i(TAG, "TEST_COMPLETE:${testCase.id}")

            TestResult(
                testCase = testCase,
                status = TestStatus.PASSED,
                durationMs = duration,
                message = "Test completed successfully",
                screenshot = "${screenshotDir.absolutePath}/${testCase.id}.png"
            )
        } catch (e: Exception) {
            Log.e(TAG, "Test failed: ${testCase.id}", e)
            val endTime = System.currentTimeMillis()
            val duration = endTime - startTime

            TestResult(
                testCase = testCase,
                status = TestStatus.FAILED,
                durationMs = duration,
                message = "Test failed: ${e.message}",
                error = e
            )
        } finally {
            _currentTest.value = null
        }
    }


    /**
     * Clear test results.
     */
    fun clearResults() {
        _testResults.value = emptyList()
    }

    /**
     * Initialize tests for navigation.
     */
    fun initializeTests(testCases: List<TestCase>) {
        if (_isRunning.value) {
            Log.w(TAG, "Tests already running")
            return
        }

        allTests = testCases
        currentTestIndex = 0
        _totalTests.value = testCases.size
        _currentTestIndex.value = 0
        _testResults.value = emptyList()

        // Run the first test
        if (testCases.isNotEmpty()) {
            runCurrentTest()
        }
    }

    /**
     * Initialize tests, optionally starting at a specific test ID.
     */
    fun initializeTestById(testId: String) {
        // Always load all tests for navigation
        val allTests = TestSuite.getAllTests()

        if (testId == "all" || testId.isEmpty()) {
            // Start from the beginning
            initializeTests(allTests)
        } else {
            // Find the starting index for the specified test
            val startIndex = allTests.indexOfFirst { it.id == testId }
            if (startIndex >= 0) {
                // Initialize with all tests but start at the specified one
                this.allTests = allTests
                currentTestIndex = startIndex
                _totalTests.value = allTests.size
                _currentTestIndex.value = startIndex
                _testResults.value = emptyList()

                // Run the specified test
                runCurrentTest()

                Log.i(TAG, "Initialized with all tests, starting at: $testId (index $startIndex)")
            } else {
                Log.w(TAG, "Test not found: $testId, starting from beginning")
                initializeTests(allTests)
            }
        }
    }

    /**
     * Move to the next test.
     */
    fun nextTest() {
        if (_isRunning.value) {
            Log.w(TAG, "Cannot move to next test: test is currently running")
            return
        }

        if (currentTestIndex < allTests.size - 1) {
            currentTestIndex++
            _currentTestIndex.value = currentTestIndex
            runCurrentTest()
        } else {
            Log.i(TAG, "Already at last test")
        }
    }

    /**
     * Move to the previous test.
     */
    fun previousTest() {
        if (_isRunning.value) {
            Log.w(TAG, "Cannot move to previous test: test is currently running")
            return
        }

        if (currentTestIndex > 0) {
            currentTestIndex--
            _currentTestIndex.value = currentTestIndex
            runCurrentTest()
        } else {
            Log.i(TAG, "Already at first test")
        }
    }

    /**
     * Check if we can go to the next test.
     */
    fun hasNextTest(): Boolean = currentTestIndex < allTests.size - 1

    /**
     * Check if we can go to the previous test.
     */
    fun hasPreviousTest(): Boolean = currentTestIndex > 0

    /**
     * Run the current test.
     */
    private fun runCurrentTest() {
        if (currentTestIndex >= allTests.size) {
            Log.w(TAG, "Test index out of bounds: $currentTestIndex")
            return
        }

        val testCase = allTests[currentTestIndex]

        scope.launch {
            _isRunning.value = true

            val result = runTest(testCase)

            // Update results list (replace if existing, append if new)
            val currentResults = _testResults.value.toMutableList()
            val existingIndex = currentResults.indexOfFirst { it.testCase.id == testCase.id }
            if (existingIndex >= 0) {
                currentResults[existingIndex] = result
            } else {
                currentResults.add(result)
            }
            _testResults.value = currentResults

            _isRunning.value = false
            Log.i(TAG, "Test completed: ${testCase.id} (${currentTestIndex + 1}/${allTests.size})")
        }
    }

    companion object {
        private const val TAG = "TestRunner"
    }
}

/**
 * Result of a single test execution.
 */
data class TestResult(
    val testCase: TestCase,
    val status: TestStatus,
    val durationMs: Long,
    val message: String,
    val error: Throwable? = null,
    val screenshot: String? = null  // Optional path to captured screenshot
)

/**
 * Test execution status.
 */
enum class TestStatus {
    PASSED,
    FAILED,
    SKIPPED
}
