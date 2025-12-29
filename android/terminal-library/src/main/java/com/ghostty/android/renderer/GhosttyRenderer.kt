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
 *
 * @param context Android context for accessing display metrics
 * @param initialFontSize Initial font size in pixels. Required - caller must provide a valid size.
 */
class GhosttyRenderer(
    private val context: Context,
    initialFontSize: Int
) : GLSurfaceView.Renderer {

    // Font size to use when surface is created. Can be updated before surface is ready
    // via setPendingFontSize(). Once surface is created, use setFontSize() instead.
    private var pendingFontSize: Int = initialFontSize

    // Track last grid size to avoid duplicate callbacks
    private var lastGridCols: Int = 0
    private var lastGridRows: Int = 0

    /**
     * Native handle for this renderer instance.
     * Each GhosttyRenderer has its own native state, allowing multiple
     * GLSurfaceViews (e.g., in RecyclerView) to coexist without conflicts.
     * This is set by native code in onSurfaceCreated and cleared in destroy.
     */
    @JvmField
    var nativeHandle: Long = 0

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
    private external fun nativeOnSurfaceChanged(width: Int, height: Int, dpi: Int, fontSize: Int)
    private external fun nativeOnDrawFrame()
    private external fun nativeDestroy()
    private external fun nativeSetTerminalSize(cols: Int, rows: Int)
    private external fun nativeSetFontSize(fontSize: Int)
    private external fun nativeProcessInput(ansiSequence: String)

    // Scrolling native methods
    private external fun nativeGetScrollbackRows(): Int
    private external fun nativeGetFontLineSpacing(): Float
    private external fun nativeGetContentHeight(): Float
    private external fun nativeScrollDelta(delta: Int)
    private external fun nativeIsViewportAtBottom(): Boolean
    private external fun nativeGetViewportOffset(): Int
    private external fun nativeScrollToBottom()
    private external fun nativeSetScrollPixelOffset(offset: Float)

    // Grid size native method - returns [cols, rows]
    private external fun nativeGetGridSize(): IntArray

    // FPS display native method
    private external fun nativeSetShowFps(show: Boolean)

    // Callback invoked after surface changes with new grid size
    private var onSurfaceChangedCallback: ((cols: Int, rows: Int) -> Unit)? = null

    /**
     * Set callback to be invoked after onSurfaceChanged completes.
     * Called with the new grid dimensions on the GL thread.
     */
    fun setOnSurfaceChangedCallback(callback: ((cols: Int, rows: Int) -> Unit)?) {
        this.onSurfaceChangedCallback = callback
    }

    /**
     * Set the font size to use when the surface is created.
     * Must be called BEFORE the surface is ready (before onSurfaceChanged runs).
     * After surface is ready, use setFontSize() instead.
     *
     * @param fontSize Font size in pixels
     */
    fun setPendingFontSize(fontSize: Int) {
        Log.d(TAG, "setPendingFontSize: $fontSize")
        this.pendingFontSize = fontSize
    }

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

        Log.d(TAG, "onSurfaceChanged: ${width}x${height} at $dpi DPI, font size: $pendingFontSize")

        try {
            nativeOnSurfaceChanged(width, height, dpi, pendingFontSize)

            // Get grid size and notify callback
            val gridSize = getGridSize()
            val cols = gridSize[0]
            val rows = gridSize[1]
            if (cols > 0 && rows > 0) {
                Log.d(TAG, "Surface ready with grid size: ${cols}x${rows}")
                // Update tracking and notify callback
                lastGridCols = cols
                lastGridRows = rows
                onSurfaceChangedCallback?.invoke(cols, rows)
            }
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
     * After font size changes, the grid dimensions change, so we notify
     * via the onSurfaceChangedCallback.
     *
     * @param fontSize Font size in pixels
     */
    fun setFontSize(fontSize: Int) {
        Log.i(TAG, "setFontSize: $fontSize")

        try {
            nativeSetFontSize(fontSize)

            // Font size change affects grid dimensions - notify callback
            val gridSize = getGridSize()
            val cols = gridSize[0]
            val rows = gridSize[1]
            if (cols > 0 && rows > 0) {
                // Skip callback if grid size hasn't changed (avoids duplicate resize events)
                if (cols == lastGridCols && rows == lastGridRows) {
                    Log.d(TAG, "Font size set, grid unchanged: ${cols}x${rows} - skipping callback")
                    return
                }
                Log.d(TAG, "Font size changed, new grid: ${cols}x${rows}")
                lastGridCols = cols
                lastGridRows = rows
                onSurfaceChangedCallback?.invoke(cols, rows)
            }
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
     * Get the content height in pixels (actual rendered content, not full grid).
     *
     * @return Content height in pixels based on cursor position
     */
    fun getContentHeight(): Float {
        return try {
            nativeGetContentHeight()
        } catch (e: Exception) {
            Log.e(TAG, "Error in nativeGetContentHeight", e)
            0f
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
     * Also resets the visual scroll pixel offset to 0.
     */
    fun scrollToBottom() {
        try {
            nativeScrollToBottom()
            // Also reset the visual scroll pixel offset
            nativeSetScrollPixelOffset(0f)
        } catch (e: Exception) {
            Log.e(TAG, "Error in nativeScrollToBottom", e)
        }
    }

    /**
     * Set the visual scroll pixel offset for smooth sub-row scrolling.
     *
     * This offset is applied in the shaders to shift content smoothly
     * between row boundaries during scroll animations. The offset should
     * be in the range [0, fontLineSpacing).
     *
     * @param offset Pixel offset for sub-row scrolling
     */
    fun setScrollPixelOffset(offset: Float) {
        try {
            nativeSetScrollPixelOffset(offset)
        } catch (e: Exception) {
            Log.e(TAG, "Error in nativeSetScrollPixelOffset", e)
        }
    }

    // ============================================================================
    // Grid Size API
    // ============================================================================

    /**
     * Get the current terminal grid size (columns and rows).
     *
     * This returns the actual grid dimensions calculated by the renderer
     * based on the surface size and font metrics.
     *
     * @return IntArray of [cols, rows], or [0, 0] if not available
     */
    fun getGridSize(): IntArray {
        return try {
            nativeGetGridSize()
        } catch (e: Exception) {
            Log.e(TAG, "Error in nativeGetGridSize", e)
            intArrayOf(0, 0)
        }
    }

    // ============================================================================
    // FPS Display API
    // ============================================================================

    /**
     * Enable or disable the FPS display overlay.
     *
     * When enabled, the current frames per second is rendered at the
     * top-right corner of the terminal.
     *
     * @param show true to show FPS, false to hide
     */
    fun setShowFps(show: Boolean) {
        try {
            nativeSetShowFps(show)
        } catch (e: Exception) {
            Log.e(TAG, "Error in nativeSetShowFps", e)
        }
    }
}
