package com.ghostty.android.renderer

import android.content.Context
import android.graphics.Canvas
import android.opengl.GLSurfaceView
import android.util.AttributeSet
import android.util.Log
import android.view.Choreographer
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

    // Visual scroll pixel offset for smooth sub-row animation (0 to fontLineSpacing)
    private var scrollPixelOffset = 0f

    // Last row position used by OverScroller (for tracking delta during fling)
    private var lastScrollerRow = 0

    // Choreographer for driving fling animation at vsync
    private val choreographer = Choreographer.getInstance()
    private var isAnimating = false

    // Frame callback for scroll animation
    private val scrollAnimationCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            // Check if we should stop animation (e.g., scrollToBottom was called externally,
            // or terminal was cleared and no longer has scrollback)
            if (renderer.isViewportAtBottom() && renderer.getScrollbackRows() == 0) {
                scroller.forceFinished(true)
                isAnimating = false
                scrollPixelOffset = 0f
                lastScrollerRow = 0
                queueEvent {
                    renderer.setScrollPixelOffset(0f)
                    requestRender()
                }
                return
            }

            if (!scroller.computeScrollOffset()) {
                // Animation finished - reset pixel offset to clean state
                isAnimating = false
                scrollPixelOffset = 0f
                queueEvent {
                    renderer.setScrollPixelOffset(0f)
                    requestRender()
                }
                return
            }

            val fontLineSpacing = renderer.getFontLineSpacing()
            val scrollbackRows = renderer.getScrollbackRows()
            val maxPixelY = scrollbackRows * fontLineSpacing

            // Clamp to valid scroll bounds - don't let overfling affect terminal state
            val currentPixelY = scroller.currY.toFloat().coerceIn(0f, maxPixelY)

            if (fontLineSpacing > 0) {
                // Calculate target row and sub-row offset from clamped pixel position
                val targetRow = (currentPixelY / fontLineSpacing).toInt().coerceAtMost(scrollbackRows)
                var newPixelOffset = currentPixelY - (targetRow * fontLineSpacing)
                newPixelOffset = newPixelOffset.coerceIn(0f, fontLineSpacing - 1f)

                // Update terminal viewport when crossing row boundaries
                val rowDelta = targetRow - lastScrollerRow
                if (rowDelta != 0) {
                    lastScrollerRow = targetRow
                    queueEvent {
                        renderer.scrollDelta(rowDelta)
                    }
                }

                // Update visual offset for smooth sub-row animation
                scrollPixelOffset = newPixelOffset
                queueEvent {
                    renderer.setScrollPixelOffset(scrollPixelOffset)
                    requestRender()
                }
            }

            // Handle edge effects at fling boundaries
            if (scroller.isOverScrolled) {
                val currVelocity = scroller.currVelocity.toInt()
                val scrollbackRows = renderer.getScrollbackRows()
                val maxPixelY = scrollbackRows * fontLineSpacing

                if (currentPixelY <= 0 && !edgeEffectTop.isFinished) {
                    edgeEffectTop.onAbsorb(currVelocity)
                } else if (currentPixelY >= maxPixelY && !edgeEffectBottom.isFinished) {
                    edgeEffectBottom.onAbsorb(currVelocity)
                }
            }

            // Continue animation on next vsync
            choreographer.postFrameCallback(this)
        }
    }

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
                if (isAnimating) {
                    choreographer.removeFrameCallback(scrollAnimationCallback)
                    isAnimating = false
                }
                // Reset visual pixel offset when touch begins
                scrollPixelOffset = 0f
                lastScrollerRow = renderer.getViewportOffset()
                queueEvent {
                    renderer.setScrollPixelOffset(0f)
                }
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

                // Accumulate scroll distance in pixels
                scrollPixelOffset += distanceY

                // Check boundaries
                val currentRow = renderer.getViewportOffset()
                val isAtTop = currentRow == 0
                val isAtBottom = renderer.isViewportAtBottom()

                // Calculate how many full rows to scroll
                var rowsDelta = 0

                // distanceY > 0 = finger moved UP = scroll DOWN (towards active area)
                // scrollPixelOffset accumulates positive values, crossing row boundaries
                if (isAtBottom && scrollPixelOffset > 0) {
                    // At bottom, can't scroll down - clamp offset and trigger edge effect
                    edgeEffectBottom.onPull(abs(distanceY) / height)
                    edgeEffectBottom.setSize(width, height)
                    scrollPixelOffset = 0f
                } else {
                    while (scrollPixelOffset >= fontLineSpacing) {
                        scrollPixelOffset -= fontLineSpacing
                        rowsDelta += 1  // Scroll down (towards active area)
                    }
                }

                // distanceY < 0 = finger moved DOWN = scroll UP (towards scrollback)
                // scrollPixelOffset goes negative, crossing row boundaries upward
                if (isAtTop && scrollPixelOffset < 0) {
                    // At top, can't scroll up - clamp offset and trigger edge effect
                    edgeEffectTop.onPull(abs(distanceY) / height)
                    edgeEffectTop.setSize(width, height)
                    scrollPixelOffset = 0f
                } else {
                    while (scrollPixelOffset < 0) {
                        scrollPixelOffset += fontLineSpacing
                        rowsDelta -= 1  // Scroll up (towards scrollback)
                    }
                }

                // Final clamp to ensure valid range
                scrollPixelOffset = scrollPixelOffset.coerceIn(0f, fontLineSpacing - 1f)

                // Apply updates to renderer
                queueEvent {
                    if (rowsDelta != 0) {
                        renderer.scrollDelta(rowsDelta)
                    }
                    renderer.setScrollPixelOffset(scrollPixelOffset)
                    requestRender()
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

                // Calculate current position in pixels for OverScroller
                // currentOffset is in rows, scrollPixelOffset is sub-row offset
                val currentOffset = renderer.getViewportOffset()
                val maxPixelY = scrollbackRows * fontLineSpacing

                // Clamp scrollPixelOffset and ensure we don't exceed bounds
                scrollPixelOffset = scrollPixelOffset.coerceIn(0f, fontLineSpacing - 1f)
                var currentPixelY = currentOffset * fontLineSpacing + scrollPixelOffset

                // Clamp starting position to valid scroll bounds
                currentPixelY = currentPixelY.coerceIn(0f, maxPixelY)

                // Initialize lastScrollerRow from pixel position to avoid jump at start
                lastScrollerRow = (currentPixelY / fontLineSpacing).toInt()

                // Start fling animation using pixel coordinates (native Android feel)
                // Android convention: fling UP (velocityY < 0) = content moves UP = see content below
                // Our convention: Y increases towards active area (bottom)
                // So fling UP should INCREASE Y, but negative velocity DECREASES Y
                // Therefore: negate velocity
                scroller.forceFinished(true)
                scroller.fling(
                    0, currentPixelY.toInt(),           // startX, startY (pixels)
                    0, -velocityY.toInt(),              // velocityX, velocityY (negated for correct direction)
                    0, 0,                               // minX, maxX
                    0, maxPixelY.toInt(),               // minY, maxY (pixels)
                    0, height / 4                       // overX, overY (allow some overfling)
                )

                // Start animation using Choreographer (runs at vsync for smooth 60fps)
                if (!isAnimating) {
                    isAnimating = true
                    choreographer.postFrameCallback(scrollAnimationCallback)
                }
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
     * Called during draw - just triggers edge effect rendering if needed.
     * Scroll animation is handled by Choreographer callback.
     */
    override fun computeScroll() {
        super.computeScroll()

        // Keep edge effects animating
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

    /**
     * Enable or disable the FPS display overlay.
     *
     * When enabled, the current frames per second is rendered at the
     * top-right corner of the terminal.
     */
    var showFps: Boolean = true
        set(value) {
            field = value
            queueEvent {
                renderer.setShowFps(value)
                requestRender()
            }
        }
}
