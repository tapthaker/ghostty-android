package com.ghostty.android.renderer

import android.content.Context
import android.opengl.GLSurfaceView
import android.util.AttributeSet
import android.util.Log
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import kotlin.math.max
import kotlin.math.min

/**
 * OpenGL ES surface view for Ghostty terminal rendering.
 *
 * This view manages the OpenGL ES context and the renderer lifecycle.
 * It handles:
 * - OpenGL ES 3.1 context creation
 * - Renderer thread management
 * - Surface lifecycle (pause/resume)
 * - Pinch-to-zoom for font size adjustment
 */
class GhosttyGLSurfaceView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : GLSurfaceView(context, attrs) {

    companion object {
        private const val TAG = "GhosttyGLSurfaceView"

        // OpenGL ES version requirements
        private const val GLES_MAJOR_VERSION = 3
        private const val GLES_CONTEXT_CLIENT_VERSION = 3 // Request ES 3.x

        // Font size constraints
        private const val MIN_FONT_SIZE = 8f
        private const val MAX_FONT_SIZE = 96f
        private const val DEFAULT_FONT_SIZE = 20f  // More reasonable default
    }

    private val renderer: GhosttyRenderer
    private val scaleGestureDetector: ScaleGestureDetector
    private var currentFontSize = DEFAULT_FONT_SIZE

    init {
        Log.d(TAG, "Initializing Ghostty GL Surface View")

        // Request OpenGL ES 3.x context
        setEGLContextClientVersion(GLES_CONTEXT_CLIENT_VERSION)

        // Configure EGL
        // RGBA8888 format (8 bits per channel)
        // No depth buffer needed for 2D rendering
        // No stencil buffer needed
        setEGLConfigChooser(
            8,  // red
            8,  // green
            8,  // blue
            8,  // alpha
            0,  // depth
            0   // stencil
        )

        // Make the GL surface visible on top of the window background
        // This is needed because GLSurfaceView renders in a separate window by default
        setZOrderOnTop(true)

        // Create and set the renderer (pass context for DPI access)
        renderer = GhosttyRenderer(context)
        setRenderer(renderer)

        // Set render mode to continuously for proof of concept
        // TODO: Change to RENDERMODE_WHEN_DIRTY once we have proper terminal update callbacks
        renderMode = RENDERMODE_CONTINUOUSLY

        // Initialize pinch-to-zoom gesture detector
        scaleGestureDetector = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            private var baseFontSize = currentFontSize  // Store the font size at the start of gesture
            private var accumulatedScale = 1f  // Track accumulated scale during the gesture
            private var lastUpdateTime = 0L
            private val UPDATE_THROTTLE_MS = 16L  // Throttle updates to max ~60 FPS for smooth scaling

            override fun onScaleBegin(detector: ScaleGestureDetector): Boolean {
                Log.d(TAG, "Pinch zoom started - current font size: $currentFontSize")
                baseFontSize = currentFontSize  // Remember font size at gesture start
                accumulatedScale = 1f  // Reset accumulated scale
                lastUpdateTime = 0L
                return true
            }

            override fun onScale(detector: ScaleGestureDetector): Boolean {
                // Throttle updates to avoid overwhelming the renderer
                val currentTime = System.currentTimeMillis()
                if (currentTime - lastUpdateTime < UPDATE_THROTTLE_MS) {
                    return true
                }

                // Get the current scale factor from the detector
                // This is a RATIO: 1.0 = no change, >1.0 = zoom in, <1.0 = zoom out
                val scaleFactor = detector.scaleFactor

                // Accumulate the scale factor
                // This gives us the total scale from the beginning of the gesture
                accumulatedScale *= scaleFactor

                // Calculate new font size based on the base size and accumulated scale
                // This ensures smooth, predictable scaling
                val newFontSize = baseFontSize * accumulatedScale

                // Clamp to valid range
                val clampedSize = max(MIN_FONT_SIZE, min(MAX_FONT_SIZE, newFontSize))

                // Only update if change is significant enough (avoid tiny updates)
                if (kotlin.math.abs(clampedSize - currentFontSize) > 0.1f) {
                    Log.i(TAG, "Font size: %.1f -> %.1f (scale factor: %.3f, accumulated: %.3f)".format(
                        currentFontSize, clampedSize, scaleFactor, accumulatedScale
                    ))
                    currentFontSize = clampedSize
                    lastUpdateTime = currentTime

                    // Update font size on GL thread
                    queueEvent {
                        renderer.setFontSize(currentFontSize.toInt())
                        requestRender()
                    }
                }

                return true
            }

            override fun onScaleEnd(detector: ScaleGestureDetector) {
                Log.d(TAG, "Pinch zoom ended - final font size: $currentFontSize")
                // Reset for next gesture
                baseFontSize = currentFontSize
                accumulatedScale = 1f
            }
        })

        Log.d(TAG, "GL Surface View initialized")
    }

    /**
     * Request a frame to be rendered.
     *
     * Call this when terminal state changes and needs to be re-rendered.
     * This is safe to call from any thread.
     */
    override fun invalidate() {
        requestRender()
    }

    /**
     * Set the terminal size in character cells.
     *
     * @param cols Number of columns
     * @param rows Number of rows
     */
    fun setTerminalSize(cols: Int, rows: Int) {
        // Queue a runnable on the GL thread to avoid threading issues
        queueEvent {
            renderer.setTerminalSize(cols, rows)
            requestRender() // Re-render with new size
        }
    }

    /**
     * Get the renderer instance.
     *
     * This allows access to the renderer for direct operations like
     * processing input for testing.
     *
     * @return The GhosttyRenderer instance
     */
    fun getRenderer(): GhosttyRenderer {
        return renderer
    }

    /**
     * Called when the view is detached from the window.
     *
     * Clean up resources here.
     */
    override fun onDetachedFromWindow() {
        Log.d(TAG, "onDetachedFromWindow")

        // Queue cleanup on the GL thread
        queueEvent {
            renderer.destroy()
        }

        super.onDetachedFromWindow()
    }

    /**
     * Handle pause lifecycle event.
     *
     * Called by the parent activity/fragment.
     */
    fun onPauseView() {
        Log.d(TAG, "onPauseView")
        renderer.onPause()
        onPause() // Pause the GL thread
    }

    /**
     * Handle resume lifecycle event.
     *
     * Called by the parent activity/fragment.
     */
    fun onResumeView() {
        Log.d(TAG, "onResumeView")
        onResume() // Resume the GL thread
        renderer.onResume()
    }

    /**
     * Handle touch events for pinch-to-zoom and other gestures.
     */
    override fun onTouchEvent(event: MotionEvent): Boolean {
        // First, let the scale gesture detector handle the event
        val scaleHandled = scaleGestureDetector.onTouchEvent(event)

        // Also handle basic touch events for future features
        if (!scaleHandled) {
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    Log.v(TAG, "Touch down at (${event.x}, ${event.y})")
                    // Future: Handle touch down
                }
                MotionEvent.ACTION_MOVE -> {
                    // Only log if not scaling
                    if (!scaleGestureDetector.isInProgress) {
                        Log.v(TAG, "Touch move to (${event.x}, ${event.y})")
                        // Future: Handle touch move (scrolling, selection)
                    }
                }
                MotionEvent.ACTION_UP -> {
                    Log.v(TAG, "Touch up at (${event.x}, ${event.y})")
                    // Future: Handle touch up
                }
            }
        }

        return true // Consume the event
    }

    /**
     * Trigger a re-render from outside the view.
     *
     * This is safe to call from any thread.
     */
    fun triggerRender() {
        requestRender()
    }
}
