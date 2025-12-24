package com.ghostty.android.terminal

import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter

/**
 * Manages a terminal session with a shell process.
 * Handles PTY communication and terminal state.
 */
class TerminalSession(
    private val shellCommand: String = "/system/bin/sh"
) {
    private val scope = CoroutineScope(Dispatchers.IO + Job())

    private var process: Process? = null
    private var writer: OutputStreamWriter? = null
    private var reader: BufferedReader? = null

    private val _output = MutableStateFlow("")
    val output: StateFlow<String> = _output.asStateFlow()

    private val _isRunning = MutableStateFlow(false)
    val isRunning: StateFlow<Boolean> = _isRunning.asStateFlow()

    /**
     * Start the shell process.
     */
    fun start() {
        if (_isRunning.value) {
            Log.w(TAG, "Session already running")
            return
        }

        try {
            // Start the shell process
            val processBuilder = ProcessBuilder(shellCommand)
            processBuilder.redirectErrorStream(true)

            process = processBuilder.start()
            writer = OutputStreamWriter(process!!.outputStream)
            reader = BufferedReader(InputStreamReader(process!!.inputStream))

            _isRunning.value = true
            Log.d(TAG, "Started shell: $shellCommand")

            // Start reading output
            scope.launch {
                readOutput()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start session", e)
            cleanup()
        }
    }

    /**
     * Write input to the shell.
     */
    fun writeInput(text: String) {
        try {
            writer?.write(text)
            writer?.flush()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to write input", e)
        }
    }

    /**
     * Send a line of input to the shell.
     */
    fun writeLine(line: String) {
        writeInput(line + "\n")
    }

    /**
     * Read output from the shell continuously.
     */
    private suspend fun readOutput() {
        try {
            val buffer = CharArray(8192)
            val outputBuilder = StringBuilder(_output.value)

            while (_isRunning.value) {
                val count = reader?.read(buffer) ?: break
                if (count <= 0) break

                val text = String(buffer, 0, count)
                outputBuilder.append(text)

                // Update the output state
                _output.value = outputBuilder.toString()

                // Limit output buffer size to prevent memory issues
                if (outputBuilder.length > MAX_OUTPUT_SIZE) {
                    outputBuilder.delete(0, outputBuilder.length - MAX_OUTPUT_SIZE)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error reading output", e)
        } finally {
            cleanup()
        }
    }

    /**
     * Stop the session and clean up resources.
     */
    fun stop() {
        cleanup()
    }

    private fun cleanup() {
        _isRunning.value = false

        try {
            writer?.close()
            reader?.close()
            process?.destroy()
        } catch (e: Exception) {
            Log.e(TAG, "Error during cleanup", e)
        }

        writer = null
        reader = null
        process = null
    }

    companion object {
        private const val TAG = "TerminalSession"
        private const val MAX_OUTPUT_SIZE = 100_000 // Keep last 100k characters
    }
}
