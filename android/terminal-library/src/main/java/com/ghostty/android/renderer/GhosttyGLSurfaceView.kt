package com.ghostty.android.renderer

import android.content.Context
import android.content.res.TypedArray
import android.graphics.Canvas
import android.opengl.GLSurfaceView
import android.util.AttributeSet
import android.util.Log
import android.view.Choreographer
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.animation.DecelerateInterpolator
import android.widget.EdgeEffect
import android.widget.OverScroller
import com.ghostty.android.R
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Unified listener for terminal events.
 * Handles surface lifecycle, keyboard gestures, and other terminal events.
 */
interface TerminalEventListener {
    /**
     * Called when terminal surface is ready with valid grid size.
     * Fires after initial creation and after every resize (orientation change, etc.).
     *
     * Expected response: clear terminal, send resize to remote, fetch fresh content.
     *
     * @param cols Terminal columns
     * @param rows Terminal rows
     */
    fun onSurfaceReady(cols: Int, rows: Int)

    /**
     * Called during drag/animation with current offset progress.
     * Used to drive keyboard visibility animation.
     *
     * @param offset Current offset in pixels (0 to maxOffset)
     * @param maxOffset Maximum offset (keyboard height)
     */
    fun onBottomOffsetChanged(offset: Float, maxOffset: Float)

    /**
     * Called when offset state changes (expanded/collapsed).
     * Used to finalize keyboard visibility animation.
     *
     * @param expanded true if keyboard area should be shown
     */
    fun onBottomOffsetStateChanged(expanded: Boolean)

    /**
     * Called when user performs a two-finger swipe up gesture.
     */
    fun onTwoFingerSwipeUp() {}

    /**
     * Called when user performs a two-finger swipe down gesture.
     */
    fun onTwoFingerSwipeDown() {}

    /**
     * Called when user performs a two-finger double-tap gesture.
     */
    fun onTwoFingerDoubleTap() {}

    /**
     * Called when user performs a single-finger double-tap gesture.
     */
    fun onDoubleTap() {}
}

/**
 * OpenGL ES surface view for Ghostty terminal rendering.
 *
 * This view manages the OpenGL ES context and the renderer lifecycle.
 * It handles:
 * - OpenGL ES 3.1 context creation
 * - Renderer thread management
 * - Surface lifecycle (pause/resume)
 * - Pinch-to-zoom for font size adjustment
 *
 * @param context Android context
 * @param attrs XML attributes (optional, for XML inflation)
 * @param initialFontSize Initial font size in pixels (optional, for programmatic construction)
 */
class GhosttyGLSurfaceView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    initialFontSize: Float = 0f
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

        // Bottom offset animation
        private const val SNAP_ANIMATION_DURATION_MS = 250L

        // Two-finger swipe thresholds
        private const val TWO_FINGER_SWIPE_THRESHOLD_DP = 50f
        private const val TWO_FINGER_SWIPE_MAX_TIME_MS = 500L
        private const val TWO_FINGER_DIRECTION_RATIO = 2.0f

        // Two-finger double-tap thresholds
        private const val TWO_FINGER_TAP_MAX_DISTANCE_DP = 20f
        private const val TWO_FINGER_TAP_MAX_TIME_MS = 200L
        private const val TWO_FINGER_DOUBLE_TAP_TIMEOUT_MS = 300L

        // Pinch detection threshold
        private const val PINCH_SCALE_THRESHOLD = 0.15f
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

    // Two-finger gesture state
    private var twoFingerGestureActive = false
    private var twoFingerStartX1 = 0f
    private var twoFingerStartY1 = 0f
    private var twoFingerStartX2 = 0f
    private var twoFingerStartY2 = 0f
    private var twoFingerStartTime = 0L
    private var lastTwoFingerTapTime = 0L
    private var twoFingerSwipeDetected = false

    // Computed pixel thresholds (set in init)
    private var twoFingerSwipeThresholdPx = 0f
    private var twoFingerTapMaxDistancePx = 0f

    // Last row position used by OverScroller (for tracking delta during fling)
    private var lastScrollerRow = 0

    // Terminal event listener
    private var eventListener: TerminalEventListener? = null
    private var maxBottomOffset = 0f              // Configurable max offset (keyboard height)
    private var bottomOffset = 0f                 // Current animated offset (0 to maxBottomOffset)
    private var bottomOffsetDragStart = 0f        // Offset when drag gesture started
    private var accumulatedBottomDrag = 0f        // Accumulated drag distance for bottom offset
    private var isBottomOffsetAnimating = false
    private var bottomOffsetAnimationStartTime = 0L
    private var bottomOffsetAnimationStartValue = 0f
    private var bottomOffsetAnimationTargetValue = 0f
    private val bottomOffsetInterpolator = DecelerateInterpolator()
    private var lastBottomOffsetExpanded = false  // Track last state for callback

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
                // Only reset if no active bottom offset
                if (bottomOffset == 0f) {
                    queueEvent {
                        renderer.setScrollPixelOffset(0f)
                        requestRender()
                    }
                }
                return
            }

            if (!scroller.computeScrollOffset()) {
                // Animation finished - reset pixel offset to clean state
                isAnimating = false
                scrollPixelOffset = 0f
                // Only reset if no active bottom offset
                if (bottomOffset == 0f) {
                    queueEvent {
                        renderer.setScrollPixelOffset(0f)
                        requestRender()
                    }
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

    // Frame callback for bottom offset snap animation
    private val bottomOffsetAnimationCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (!isBottomOffsetAnimating) return

            val elapsed = System.currentTimeMillis() - bottomOffsetAnimationStartTime
            val progress = (elapsed.toFloat() / SNAP_ANIMATION_DURATION_MS).coerceIn(0f, 1f)
            val interpolatedProgress = bottomOffsetInterpolator.getInterpolation(progress)

            bottomOffset = bottomOffsetAnimationStartValue +
                (bottomOffsetAnimationTargetValue - bottomOffsetAnimationStartValue) * interpolatedProgress

            // Apply offset via renderer
            queueEvent {
                renderer.setScrollPixelOffset(bottomOffset)
                requestRender()
            }

            // Notify listener of offset change
            eventListener?.onBottomOffsetChanged(bottomOffset, maxBottomOffset)

            if (progress >= 1f) {
                // Animation complete
                isBottomOffsetAnimating = false
                bottomOffset = bottomOffsetAnimationTargetValue

                // Notify state change if it changed
                val isExpanded = bottomOffset >= maxBottomOffset
                if (isExpanded != lastBottomOffsetExpanded) {
                    lastBottomOffsetExpanded = isExpanded
                    eventListener?.onBottomOffsetStateChanged(isExpanded)
                }
            } else {
                // Continue animation
                choreographer.postFrameCallback(this)
            }
        }
    }

    init {
        Log.d(TAG, "Initializing Ghostty GL Surface View")

        // Parse XML attributes if present
        val resolvedFontSize = if (attrs != null) {
            val typedArray: TypedArray = context.obtainStyledAttributes(
                attrs,
                R.styleable.GhosttyGLSurfaceView
            )
            try {
                // getDimension returns pixels, or default value if not specified
                val xmlFontSize = typedArray.getDimension(
                    R.styleable.GhosttyGLSurfaceView_initialFontSize,
                    0f
                )
                // Use XML value if specified, otherwise use constructor parameter
                if (xmlFontSize > 0f) xmlFontSize else initialFontSize
            } finally {
                typedArray.recycle()
            }
        } else {
            // No XML attributes, use constructor parameter
            initialFontSize
        }

        // Set current font size: use resolved value if specified, otherwise use default
        currentFontSize = if (resolvedFontSize > 0f) resolvedFontSize else DEFAULT_FONT_SIZE
        Log.d(TAG, "Initial font size: $currentFontSize px")

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

        // Create and set the renderer (pass context for DPI access and initial font size)
        // Pass 0 if using default font size, otherwise pass the resolved font size as int
        val rendererFontSize = if (resolvedFontSize > 0f) resolvedFontSize.toInt() else 0
        renderer = GhosttyRenderer(context, rendererFontSize)
        setRenderer(renderer)

        // Set up surface change callback to notify listener on main thread
        renderer.setOnSurfaceChangedCallback { cols, rows ->
            // Post to main thread since we're on GL thread
            post {
                eventListener?.onSurfaceReady(cols, rows)
            }
        }

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
                // Abort any ongoing bottom offset animation
                if (isBottomOffsetAnimating) {
                    choreographer.removeFrameCallback(bottomOffsetAnimationCallback)
                    isBottomOffsetAnimating = false
                }
                // Reset visual pixel offset when touch begins
                scrollPixelOffset = 0f
                lastScrollerRow = renderer.getViewportOffset()
                // Reset bottom offset drag tracking
                bottomOffsetDragStart = bottomOffset
                accumulatedBottomDrag = bottomOffset  // Start from current offset
                // Preserve bottom offset if active, otherwise reset to 0
                queueEvent {
                    renderer.setScrollPixelOffset(bottomOffset)
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

                // Handle bottom offset mode (for keyboard area)
                // Enter this mode when: at bottom and swiping up, OR already have offset
                if (maxBottomOffset > 0 && (bottomOffset > 0 || (isAtBottom && distanceY > 0))) {
                    accumulatedBottomDrag += distanceY
                    val newOffset = accumulatedBottomDrag.coerceIn(0f, maxBottomOffset)
                    if (newOffset != bottomOffset) {
                        bottomOffset = newOffset
                        queueEvent {
                            renderer.setScrollPixelOffset(bottomOffset)
                            requestRender()
                        }
                        eventListener?.onBottomOffsetChanged(bottomOffset, maxBottomOffset)
                    }
                    // Reset scrollPixelOffset so normal scrolling starts fresh when we exit
                    scrollPixelOffset = 0f
                    return true
                }

                // distanceY > 0 = finger moved UP = scroll DOWN (towards active area)
                // scrollPixelOffset accumulates positive values, crossing row boundaries
                if (isAtBottom && scrollPixelOffset > 0) {
                    // At bottom, can't scroll down - show edge effect
                    edgeEffectBottom.onPull(abs(distanceY) / height)
                    edgeEffectBottom.setSize(width, height)
                    scrollPixelOffset = 0f
                } else {
                    // Normal scroll - handle row crossings
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

                // Don't fling if we're in bottom offset mode - let the snap animation handle it
                if (bottomOffset > 0 || (maxBottomOffset > 0 && renderer.isViewportAtBottom() && velocityY < 0)) {
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

            override fun onDoubleTap(e: MotionEvent): Boolean {
                Log.d(TAG, "Single-finger double tap detected")
                eventListener?.onDoubleTap()
                return true
            }
        })

        // Initialize OverScroller for fling physics
        scroller = OverScroller(context)

        // Initialize edge effects for overscroll feedback
        edgeEffectTop = EdgeEffect(context)
        edgeEffectBottom = EdgeEffect(context)

        // Compute pixel thresholds from DP values
        val density = context.resources.displayMetrics.density
        twoFingerSwipeThresholdPx = TWO_FINGER_SWIPE_THRESHOLD_DP * density
        twoFingerTapMaxDistancePx = TWO_FINGER_TAP_MAX_DISTANCE_DP * density

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

        // Track two-finger gestures
        handleTwoFingerGesture(event)

        // Let scroll gesture detector handle the event
        // Only process scroll if we're not in a scale gesture or two-finger gesture
        val scrollHandled = if (!scaleGestureDetector.isInProgress && !twoFingerGestureActive) {
            gestureDetector.onTouchEvent(event)
        } else {
            false
        }

        // Handle edge effect release and bottom offset snap on ACTION_UP or ACTION_CANCEL
        when (event.actionMasked) {
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                // Handle bottom offset snap animation
                if (maxBottomOffset > 0 && (bottomOffset > 0 || accumulatedBottomDrag != 0f)) {
                    // Snap to nearest: if past 50%, expand; otherwise collapse
                    val target = if (bottomOffset > maxBottomOffset / 2) maxBottomOffset else 0f
                    animateBottomOffsetTo(target)
                    accumulatedBottomDrag = 0f
                }

                edgeEffectTop.onRelease()
                edgeEffectBottom.onRelease()
                if (!edgeEffectTop.isFinished || !edgeEffectBottom.isFinished) {
                    postInvalidateOnAnimation()
                }

                // Reset two-finger gesture state
                resetTwoFingerGestureState()
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

    /**
     * Set the maximum bottom offset (keyboard height).
     *
     * When set to a positive value, the user can swipe up at the bottom
     * of the terminal to reveal this offset area for the keyboard.
     *
     * @param height Maximum offset in pixels (typically keyboard height)
     */
    fun setMaxBottomOffset(height: Float) {
        this.maxBottomOffset = height.coerceAtLeast(0f)
    }

    /**
     * Set the listener for terminal events.
     *
     * The listener receives:
     * - onSurfaceReady: when terminal surface is ready or resized
     * - onBottomOffsetChanged: during keyboard gesture drag/animation
     * - onBottomOffsetStateChanged: when keyboard gesture state changes
     */
    fun setEventListener(listener: TerminalEventListener?) {
        this.eventListener = listener
    }

    /**
     * Get the current bottom offset value.
     *
     * @return Current offset in pixels (0 to maxBottomOffset)
     */
    fun getBottomOffset(): Float = bottomOffset

    /**
     * Check if the bottom offset is fully expanded.
     *
     * @return true if offset equals maxBottomOffset and maxBottomOffset > 0
     */
    fun isBottomOffsetExpanded(): Boolean = maxBottomOffset > 0 && bottomOffset >= maxBottomOffset

    /**
     * Animate the bottom offset to a target value.
     * Used internally for snap animations after gesture end.
     */
    private fun animateBottomOffsetTo(target: Float) {
        if (isBottomOffsetAnimating) {
            choreographer.removeFrameCallback(bottomOffsetAnimationCallback)
        }

        bottomOffsetAnimationStartTime = System.currentTimeMillis()
        bottomOffsetAnimationStartValue = bottomOffset
        bottomOffsetAnimationTargetValue = target.coerceIn(0f, maxBottomOffset)
        isBottomOffsetAnimating = true

        choreographer.postFrameCallback(bottomOffsetAnimationCallback)
    }

    /**
     * Check if the current gesture is predominantly a pinch (scale) gesture.
     */
    private fun isPinchGesture(): Boolean {
        if (!scaleGestureDetector.isInProgress) return false
        val scaleFactor = scaleGestureDetector.scaleFactor
        return abs(scaleFactor - 1.0f) > PINCH_SCALE_THRESHOLD
    }

    /**
     * Reset two-finger gesture tracking state.
     */
    private fun resetTwoFingerGestureState() {
        twoFingerGestureActive = false
        twoFingerSwipeDetected = false
    }

    /**
     * Handle two-finger gesture tracking.
     */
    private fun handleTwoFingerGesture(event: MotionEvent) {
        when (event.actionMasked) {
            MotionEvent.ACTION_POINTER_DOWN -> {
                // Second finger touched - start tracking two-finger gesture
                if (event.pointerCount == 2) {
                    twoFingerGestureActive = true
                    twoFingerSwipeDetected = false
                    twoFingerStartTime = System.currentTimeMillis()
                    twoFingerStartX1 = event.getX(0)
                    twoFingerStartY1 = event.getY(0)
                    twoFingerStartX2 = event.getX(1)
                    twoFingerStartY2 = event.getY(1)
                }
            }

            MotionEvent.ACTION_MOVE -> {
                if (twoFingerGestureActive && event.pointerCount == 2 && !twoFingerSwipeDetected) {
                    // Don't process if this is a pinch gesture
                    if (isPinchGesture()) {
                        return
                    }
                    // Check for swipe gesture during movement
                    checkTwoFingerSwipe(event)
                }
            }

            MotionEvent.ACTION_POINTER_UP -> {
                // When one finger lifts while we have 2 fingers, finalize two-finger gesture
                if (event.pointerCount == 2 && twoFingerGestureActive) {
                    finalizeTwoFingerGesture(event)
                }
            }
        }
    }

    /**
     * Check if the current movement constitutes a two-finger swipe.
     */
    private fun checkTwoFingerSwipe(event: MotionEvent) {
        val elapsedTime = System.currentTimeMillis() - twoFingerStartTime
        if (elapsedTime > TWO_FINGER_SWIPE_MAX_TIME_MS) {
            return  // Too slow for swipe
        }

        // Calculate average movement of both fingers
        val dx1 = event.getX(0) - twoFingerStartX1
        val dy1 = event.getY(0) - twoFingerStartY1
        val dx2 = event.getX(1) - twoFingerStartX2
        val dy2 = event.getY(1) - twoFingerStartY2

        val avgDy = (dy1 + dy2) / 2f

        // Check if both fingers moved in the same vertical direction (parallel movement)
        val sameDirection = (dy1 * dy2 > 0)
        if (!sameDirection) {
            return  // Fingers moving in opposite directions (likely pinch)
        }

        // Check if movement is primarily vertical and exceeds threshold
        val absAvgDx = abs((dx1 + dx2) / 2f)
        val absAvgDy = abs(avgDy)

        if (absAvgDy < twoFingerSwipeThresholdPx) {
            return  // Not enough vertical movement
        }

        if (absAvgDx > 0 && absAvgDy / absAvgDx < TWO_FINGER_DIRECTION_RATIO) {
            return  // Not vertical enough (might be diagonal or horizontal)
        }

        // Swipe detected!
        twoFingerSwipeDetected = true

        if (avgDy < 0) {
            // Swipe up (negative Y = up in Android coordinates)
            Log.d(TAG, "Two-finger swipe UP detected")
            eventListener?.onTwoFingerSwipeUp()
        } else {
            // Swipe down (positive Y = down)
            Log.d(TAG, "Two-finger swipe DOWN detected")
            eventListener?.onTwoFingerSwipeDown()
        }
    }

    /**
     * Finalize two-finger gesture when one finger lifts.
     * Check for double-tap pattern.
     */
    private fun finalizeTwoFingerGesture(event: MotionEvent) {
        if (!twoFingerGestureActive) return

        val elapsedTime = System.currentTimeMillis() - twoFingerStartTime

        // If no swipe was detected and gesture was quick, check for tap
        if (!twoFingerSwipeDetected && elapsedTime < TWO_FINGER_TAP_MAX_TIME_MS) {
            // Calculate total movement for both fingers
            val dx1 = abs(event.getX(0) - twoFingerStartX1)
            val dy1 = abs(event.getY(0) - twoFingerStartY1)
            val dx2 = abs(event.getX(1) - twoFingerStartX2)
            val dy2 = abs(event.getY(1) - twoFingerStartY2)

            val maxMovement = maxOf(dx1, dy1, dx2, dy2)

            if (maxMovement < twoFingerTapMaxDistancePx) {
                // This is a valid two-finger tap
                val currentTime = System.currentTimeMillis()

                if (currentTime - lastTwoFingerTapTime < TWO_FINGER_DOUBLE_TAP_TIMEOUT_MS) {
                    // Double tap detected!
                    Log.d(TAG, "Two-finger DOUBLE TAP detected")
                    eventListener?.onTwoFingerDoubleTap()
                    lastTwoFingerTapTime = 0L  // Reset to avoid triple-tap detection
                } else {
                    // First tap, wait for second
                    lastTwoFingerTapTime = currentTime
                }
            }
        }

        resetTwoFingerGestureState()
    }
}
