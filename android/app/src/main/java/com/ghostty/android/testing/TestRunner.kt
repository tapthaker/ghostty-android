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
            delay(100)  // Give terminal time to clear

            // Inject the ANSI sequence
            renderer.processInput(testCase.ansiSequence)

            // Wait for rendering to complete
            delay(500)

            Log.i(TAG, "TEST_READY:${testCase.id}")

            // Wait a bit more for screenshot capture
            delay(1000)

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
     * Run multiple test cases sequentially.
     *
     * @param testCases List of tests to execute
     */
    fun runTests(testCases: List<TestCase>) {
        if (_isRunning.value) {
            Log.w(TAG, "Tests already running")
            return
        }

        scope.launch {
            _isRunning.value = true
            _testResults.value = emptyList()

            val results = mutableListOf<TestResult>()

            for (testCase in testCases) {
                val result = runTest(testCase)
                results.add(result)
                _testResults.value = results.toList()

                // Delay between tests
                delay(1000)
            }

            _isRunning.value = false
            Log.i(TAG, "All tests completed: ${results.size} tests run")
        }
    }

    /**
     * Run all tests in a suite.
     */
    fun runAllTests() {
        runTests(TestSuite.getAllTests())
    }

    /**
     * Run tests with a specific tag.
     */
    fun runTestsByTag(tag: String) {
        runTests(TestSuite.getTestsByTag(tag))
    }

    /**
     * Run a specific test by ID.
     */
    fun runTestById(testId: String) {
        val testCase = TestSuite.getTestById(testId)
        if (testCase != null) {
            runTests(listOf(testCase))
        } else {
            Log.w(TAG, "Test not found: $testId")
        }
    }

    /**
     * Clear test results.
     */
    fun clearResults() {
        _testResults.value = emptyList()
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
