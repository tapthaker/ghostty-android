package com.ghostty.android.renderer

import android.content.Context
import android.graphics.Canvas
import android.opengl.GLSurfaceView
import android.util.AttributeSet
import android.util.Log
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.widget.EdgeEffect
import android.widget.OverScroller
import kotlin.math.abs
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
    private val gestureDetector: GestureDetector
    private val scroller: OverScroller
    private val edgeEffectTop: EdgeEffect
    private val edgeEffectBottom: EdgeEffect
    private var currentFontSize = DEFAULT_FONT_SIZE

    // Accumulated scroll distance for sub-row scrolling
    private var scrollAccumulator = 0f

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

        // Initialize scroll gesture detector
        gestureDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(e: MotionEvent): Boolean {
                // Abort any ongoing fling animation
                scroller.forceFinished(true)
                scrollAccumulator = 0f
                return true
            }

            override fun onScroll(
                e1: MotionEvent?,
                e2: MotionEvent,
                distanceX: Float,
                distanceY: Float
            ): Boolean {
                // Don't scroll if we're in a scale gesture
                if (scaleGestureDetector.isInProgress) {
                    return false
                }

                // Get font line spacing for converting pixels to rows
                val fontLineSpacing = renderer.getFontLineSpacing()
                if (fontLineSpacing <= 0) return false

                // Accumulate scroll distance
                scrollAccumulator += distanceY

                // Calculate how many full rows to scroll
                val rowsDelta = (scrollAccumulator / fontLineSpacing).toInt()

                if (rowsDelta != 0) {
                    // Remove the scrolled amount from accumulator
                    scrollAccumulator -= rowsDelta * fontLineSpacing

                    // Scroll the viewport
                    // Android natural scrolling: distanceY > 0 means finger moved up
                    // This should scroll DOWN (towards newer content, positive delta)
                    // distanceY < 0 means finger moved down, scroll UP (towards older, negative delta)
                    queueEvent {
                        renderer.scrollDelta(rowsDelta)
                        requestRender()
                    }

                    // Handle edge effects at boundaries
                    val scrollbackRows = renderer.getScrollbackRows()
                    val isAtTop = renderer.getViewportOffset() == 0
                    val isAtBottom = renderer.isViewportAtBottom()

                    // rowsDelta > 0 means scrolling down (towards bottom/active area)
                    // rowsDelta < 0 means scrolling up (towards top/scrollback)
                    if (isAtTop && rowsDelta < 0) {
                        // Trying to scroll past the top (into more scrollback) - trigger top edge effect
                        edgeEffectTop.onPull(abs(distanceY) / height)
                        edgeEffectTop.setSize(width, height)
                    } else if (isAtBottom && rowsDelta > 0) {
                        // Trying to scroll past the bottom (beyond active area) - trigger bottom edge effect
                        edgeEffectBottom.onPull(abs(distanceY) / height)
                        edgeEffectBottom.setSize(width, height)
                    }
                }

                return true
            }

            override fun onFling(
                e1: MotionEvent?,
                e2: MotionEvent,
                velocityX: Float,
                velocityY: Float
            ): Boolean {
                // Don't fling if we're in a scale gesture
                if (scaleGestureDetector.isInProgress) {
                    return false
                }

                val scrollbackRows = renderer.getScrollbackRows()
                if (scrollbackRows == 0) return false

                val fontLineSpacing = renderer.getFontLineSpacing()
                if (fontLineSpacing <= 0) return false

                // Convert velocity from pixels to rows
                // Scale down velocity for smoother feel
                val velocityInRows = (velocityY / fontLineSpacing * 0.5f).toInt()

                // Get current and max positions (in rows)
                val currentOffset = renderer.getViewportOffset()
                val maxOffset = scrollbackRows

                // Start fling animation
                // startY = current offset, we want to scroll from 0 to maxOffset
                scroller.forceFinished(true)
                scroller.fling(
                    0, currentOffset,           // startX, startY
                    0, velocityInRows,          // velocityX, velocityY
                    0, 0,                       // minX, maxX
                    0, maxOffset,               // minY, maxY (0 = top, maxOffset = bottom)
                    0, height / 4               // overX, overY (allow some overfling)
                )

                postInvalidateOnAnimation()
                return true
            }
        })

        // Initialize OverScroller for fling physics
        scroller = OverScroller(context)

        // Initialize edge effects for overscroll feedback
        edgeEffectTop = EdgeEffect(context)
        edgeEffectBottom = EdgeEffect(context)

        Log.d(TAG, "GL Surface View initialized")
    }

    /**
     * Called during draw to update scroller animation and edge effects.
     */
    override fun computeScroll() {
        super.computeScroll()

        if (scroller.computeScrollOffset()) {
            // Scroller is still animating
            val currentY = scroller.currY
            val prevOffset = renderer.getViewportOffset()

            if (currentY != prevOffset) {
                val delta = currentY - prevOffset

                // Update viewport on GL thread
                queueEvent {
                    renderer.scrollDelta(delta)
                    requestRender()
                }
            }

            // Handle edge effects at fling boundaries
            if (scroller.isOverScrolled) {
                val currVelocity = scroller.currVelocity.toInt()
                if (currentY <= 0 && !edgeEffectTop.isFinished) {
                    edgeEffectTop.onAbsorb(currVelocity)
                } else if (currentY >= renderer.getScrollbackRows() && !edgeEffectBottom.isFinished) {
                    edgeEffectBottom.onAbsorb(currVelocity)
                }
            }

            // Continue animation
            postInvalidateOnAnimation()
        }

        // Always draw edge effects if active
        if (!edgeEffectTop.isFinished || !edgeEffectBottom.isFinished) {
            postInvalidateOnAnimation()
        }
    }

    /**
     * Draw edge effects on top of the GL surface.
     */
    override fun draw(canvas: Canvas) {
        super.draw(canvas)

        // Draw top edge effect
        if (!edgeEffectTop.isFinished) {
            val restoreCount = canvas.save()
            edgeEffectTop.setSize(width, height)
            if (edgeEffectTop.draw(canvas)) {
                postInvalidateOnAnimation()
            }
            canvas.restoreToCount(restoreCount)
        }

        // Draw bottom edge effect
        if (!edgeEffectBottom.isFinished) {
            val restoreCount = canvas.save()
            canvas.translate(0f, height.toFloat())
            canvas.rotate(180f, width / 2f, 0f)
            edgeEffectBottom.setSize(width, height)
            if (edgeEffectBottom.draw(canvas)) {
                postInvalidateOnAnimation()
            }
            canvas.restoreToCount(restoreCount)
        }
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
     * Handle touch events for pinch-to-zoom, scrolling, and other gestures.
     */
    override fun onTouchEvent(event: MotionEvent): Boolean {
        // Let both gesture detectors process the event
        // Scale detector should take priority
        val scaleHandled = scaleGestureDetector.onTouchEvent(event)

        // Let scroll gesture detector handle the event
        // Only process scroll if we're not in a scale gesture
        val scrollHandled = if (!scaleGestureDetector.isInProgress) {
            gestureDetector.onTouchEvent(event)
        } else {
            false
        }

        // Handle edge effect release on ACTION_UP or ACTION_CANCEL
        when (event.action) {
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                edgeEffectTop.onRelease()
                edgeEffectBottom.onRelease()
                if (!edgeEffectTop.isFinished || !edgeEffectBottom.isFinished) {
                    postInvalidateOnAnimation()
                }
            }
        }

        return scaleHandled || scrollHandled || true // Consume the event
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
