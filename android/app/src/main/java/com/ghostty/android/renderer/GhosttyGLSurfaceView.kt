package com.ghostty.android.renderer

import android.content.Context
import android.opengl.GLSurfaceView
import android.util.AttributeSet
import android.util.Log
import android.view.MotionEvent

/**
 * OpenGL ES surface view for Ghostty terminal rendering.
 *
 * This view manages the OpenGL ES context and the renderer lifecycle.
 * It handles:
 * - OpenGL ES 3.1 context creation
 * - Renderer thread management
 * - Surface lifecycle (pause/resume)
 * - Input events (future)
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
    }

    private val renderer: GhosttyRenderer

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

        // Create and set the renderer
        renderer = GhosttyRenderer()
        setRenderer(renderer)

        // Set render mode to only render when explicitly requested
        // This saves battery compared to RENDERMODE_CONTINUOUSLY
        // We'll call requestRender() when terminal state changes
        renderMode = RENDERMODE_WHEN_DIRTY

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
     * Handle touch events (future implementation).
     *
     * Currently just logs the event.
     * Future: Implement touch-based scrolling, selection, etc.
     */
    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                Log.v(TAG, "Touch down at (${event.x}, ${event.y})")
                // Future: Handle touch down
            }
            MotionEvent.ACTION_MOVE -> {
                Log.v(TAG, "Touch move to (${event.x}, ${event.y})")
                // Future: Handle touch move (scrolling, selection)
            }
            MotionEvent.ACTION_UP -> {
                Log.v(TAG, "Touch up at (${event.x}, ${event.y})")
                // Future: Handle touch up
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
