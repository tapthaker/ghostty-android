package com.ghostty.android.renderer

import android.content.Context
import android.opengl.GLSurfaceView
import android.util.Log
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

/**
 * OpenGL ES renderer for Ghostty terminal.
 *
 * This class implements the GLSurfaceView.Renderer interface and delegates
 * all rendering operations to the native Zig renderer via JNI.
 */
class GhosttyRenderer(private val context: Context) : GLSurfaceView.Renderer {

    companion object {
        private const val TAG = "GhosttyRenderer"

        init {
            try {
                // Load native libraries
                // Note: libghostty-vt.so should already be loaded by GhosttyBridge
                System.loadLibrary("ghostty_renderer")
                Log.i(TAG, "Successfully loaded libghostty_renderer.so")
            } catch (e: UnsatisfiedLinkError) {
                Log.e(TAG, "Failed to load native renderer library", e)
                throw e
            }
        }
    }

    // Native method declarations
    private external fun nativeOnSurfaceCreated()
    private external fun nativeOnSurfaceChanged(width: Int, height: Int, dpi: Int)
    private external fun nativeOnDrawFrame()
    private external fun nativeDestroy()
    private external fun nativeSetTerminalSize(cols: Int, rows: Int)
    private external fun nativeSetFontSize(fontSize: Int)
    private external fun nativeProcessInput(ansiSequence: String)

    // Scrolling native methods
    private external fun nativeGetScrollbackRows(): Int
    private external fun nativeGetFontLineSpacing(): Float
    private external fun nativeScrollDelta(delta: Int)
    private external fun nativeIsViewportAtBottom(): Boolean
    private external fun nativeGetViewportOffset(): Int
    private external fun nativeScrollToBottom()

    /**
     * Called when the OpenGL surface is created.
     *
     * This is called on the GL thread when the surface is first created,
     * or when the OpenGL context needs to be recreated (e.g., after
     * the app returns from the background).
     */
    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        Log.d(TAG, "onSurfaceCreated")

        try {
            nativeOnSurfaceCreated()
        } catch (e: Exception) {
            Log.e(TAG, "Error in nativeOnSurfaceCreated", e)
            throw e
        }
    }

    /**
     * Called when the OpenGL surface size changes.
     *
     * This is called when the surface is created or resized (e.g., during
     * screen rotation or multi-window mode changes).
     *
     * @param gl The GL10 interface (not used, we use native GLES3)
     * @param width The new surface width in pixels
     * @param height The new surface height in pixels
     */
    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        // Get the display density (DPI) from Android
        val displayMetrics = context.resources.displayMetrics
        val dpi = displayMetrics.densityDpi // This is an integer DPI value

        Log.d(TAG, "onSurfaceChanged: ${width}x${height} at $dpi DPI")

        try {
            nativeOnSurfaceChanged(width, height, dpi)
        } catch (e: Exception) {
            Log.e(TAG, "Error in nativeOnSurfaceChanged", e)
            throw e
        }
    }

    /**
     * Called to render a frame.
     *
     * This is called on the GL thread for each frame. The frequency
     * depends on the render mode set on the GLSurfaceView.
     *
     * @param gl The GL10 interface (not used, we use native GLES3)
     */
    override fun onDrawFrame(gl: GL10?) {
        try {
            nativeOnDrawFrame()
        } catch (e: Exception) {
            Log.e(TAG, "Error in nativeOnDrawFrame", e)
            // Don't throw here to avoid crashing the render thread
            // Just log and continue
        }
    }

    /**
     * Clean up renderer resources.
     *
     * Call this when the renderer is no longer needed.
     * Should be called on the GL thread.
     */
    fun destroy() {
        Log.d(TAG, "destroy")

        try {
            nativeDestroy()
        } catch (e: Exception) {
            Log.e(TAG, "Error in nativeDestroy", e)
        }
    }

    /**
     * Set the terminal size in character cells.
     *
     * @param cols Number of columns
     * @param rows Number of rows
     */
    fun setTerminalSize(cols: Int, rows: Int) {
        Log.d(TAG, "setTerminalSize: ${cols}x${rows}")

        try {
            nativeSetTerminalSize(cols, rows)
        } catch (e: Exception) {
            Log.e(TAG, "Error in nativeSetTerminalSize", e)
        }
    }

    /**
     * Called when the render thread is paused.
     */
    fun onPause() {
        Log.d(TAG, "onPause")
        // Future: Could pause background work here
    }

    /**
     * Called when the render thread is resumed.
     */
    fun onResume() {
        Log.d(TAG, "onResume")
        // Future: Could resume background work here
    }

    /**
     * Update the font size dynamically.
     *
     * This will rebuild the font atlas and update the renderer.
     *
     * @param fontSize Font size in pixels
     */
    fun setFontSize(fontSize: Int) {
        Log.i(TAG, "setFontSize: $fontSize")

        try {
            nativeSetFontSize(fontSize)
        } catch (e: Exception) {
            Log.e(TAG, "Error in nativeSetFontSize", e)
        }
    }

    /**
     * Process ANSI input (inject ANSI escape sequences into the VT emulator).
     *
     * This feeds the input directly to the terminal manager, bypassing the shell.
     * Useful for testing and direct terminal manipulation.
     *
     * @param ansiSequence The ANSI escape sequence string to process
     */
    fun processInput(ansiSequence: String) {
        Log.d(TAG, "processInput: ${ansiSequence.length} bytes")

        try {
            nativeProcessInput(ansiSequence)
        } catch (e: Exception) {
            Log.e(TAG, "Error in nativeProcessInput", e)
        }
    }

    // ============================================================================
    // Scrolling API
    // ============================================================================

    /**
     * Get the number of scrollback rows available.
     *
     * @return Number of rows above the active area that can be scrolled to
     */
    fun getScrollbackRows(): Int {
        return try {
            nativeGetScrollbackRows()
        } catch (e: Exception) {
            Log.e(TAG, "Error in nativeGetScrollbackRows", e)
            0
        }
    }

    /**
     * Get the font line spacing (cell height) for scroll calculations.
     *
     * @return Cell height in pixels
     */
    fun getFontLineSpacing(): Float {
        return try {
            nativeGetFontLineSpacing()
        } catch (e: Exception) {
            Log.e(TAG, "Error in nativeGetFontLineSpacing", e)
            20f
        }
    }

    /**
     * Scroll the viewport by a delta number of rows.
     *
     * Positive delta scrolls down (towards newer content/active area).
     * Negative delta scrolls up (towards older content/scrollback).
     *
     * @param delta Number of rows to scroll (positive = down, negative = up)
     */
    fun scrollDelta(delta: Int) {
        try {
            nativeScrollDelta(delta)
        } catch (e: Exception) {
            Log.e(TAG, "Error in nativeScrollDelta", e)
        }
    }

    /**
     * Check if viewport is at the bottom (following active area).
     *
     * @return true if at bottom, false if scrolled up
     */
    fun isViewportAtBottom(): Boolean {
        return try {
            nativeIsViewportAtBottom()
        } catch (e: Exception) {
            Log.e(TAG, "Error in nativeIsViewportAtBottom", e)
            true
        }
    }

    /**
     * Get the current scroll offset from the top.
     *
     * @return Offset in rows (0 = at top of scrollback)
     */
    fun getViewportOffset(): Int {
        return try {
            nativeGetViewportOffset()
        } catch (e: Exception) {
            Log.e(TAG, "Error in nativeGetViewportOffset", e)
            0
        }
    }

    /**
     * Scroll viewport to the bottom (active area).
     */
    fun scrollToBottom() {
        try {
            nativeScrollToBottom()
        } catch (e: Exception) {
            Log.e(TAG, "Error in nativeScrollToBottom", e)
        }
    }
}
