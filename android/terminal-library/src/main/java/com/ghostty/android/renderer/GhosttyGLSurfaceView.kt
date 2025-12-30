package com.ghostty.android.renderer

import android.content.Context
import android.content.res.TypedArray
import android.graphics.Canvas
import android.opengl.GLSurfaceView
import android.util.AttributeSet
import android.util.Log
import android.util.TypedValue
import android.view.Choreographer
import android.view.GestureDetector
import android.view.MotionEvent
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
     * Called during drag/animation with current keyboard overlay offset progress.
     * Used to drive keyboard visibility animation.
     *
     * @param offset Current offset in pixels (0 to maxOffset)
     * @param maxOffset Maximum offset (keyboard height)
     */
    fun onKeyboardOverlayProgress(offset: Float, maxOffset: Float)

    /**
     * Called when keyboard overlay state changes (expanded/collapsed).
     * Used to finalize keyboard visibility animation.
     *
     * @param expanded true if keyboard area should be shown
     */
    fun onKeyboardOverlayStateChanged(expanded: Boolean)

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

    /**
     * Called when user completes a text selection.
     * Consumer should handle the selected text (copy to clipboard, show menu, etc.)
     *
     * @param text The selected text content
     */
    fun onTextSelected(text: String) {}

    /**
     * Called when user taps on a hyperlink (OSC 8).
     * Consumer should handle the link (open browser, show confirmation, etc.)
     *
     * @param uri The hyperlink URI
     */
    fun onHyperlinkClicked(uri: String) {}
}

/**
 * OpenGL ES surface view for Ghostty terminal rendering.
 *
 * This view manages the OpenGL ES context and the renderer lifecycle.
 * It handles:
 * - OpenGL ES 3.1 context creation
 * - Renderer thread management
 * - Surface lifecycle (pause/resume)
 * - Touch gestures (scrolling, double-tap, two-finger swipes)
 *
 * Font size can be changed programmatically via [setFontSize].
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

        // Font size defaults (can be overridden per instance)
        private const val DEFAULT_MIN_FONT_SIZE = 8f
        private const val DEFAULT_MAX_FONT_SIZE = 96f
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
    }

    private val renderer: GhosttyRenderer
    private val gestureDetector: GestureDetector
    private val scroller: OverScroller
    private val edgeEffectTop: EdgeEffect
    private val edgeEffectBottom: EdgeEffect
    private var currentFontSize = DEFAULT_FONT_SIZE

    // Configurable font size bounds (can be set via XML or programmatically)
    private var minFontSize = DEFAULT_MIN_FONT_SIZE
    private var maxFontSize = DEFAULT_MAX_FONT_SIZE

    // Interactive mode - when false, touch events are not processed
    private var isInteractive = true

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
    private var shouldScrollContentWithOverlay = true  // Whether to scroll content when overlay expands

    // Selection mode state
    private var isSelectionMode = false
    private var selectionStartX = 0f
    private var selectionStartY = 0f

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

            // Apply offset via renderer only if content needs to scroll
            queueEvent {
                val scrollOffset = if (shouldScrollContentWithOverlay) bottomOffset else 0f
                renderer.setScrollPixelOffset(scrollOffset)
                requestRender()
            }

            // Notify listener of offset change
            eventListener?.onKeyboardOverlayProgress(bottomOffset, maxBottomOffset)

            if (progress >= 1f) {
                // Animation complete
                isBottomOffsetAnimating = false
                bottomOffset = bottomOffsetAnimationTargetValue

                // Notify state change if it changed
                val isExpanded = bottomOffset >= maxBottomOffset
                if (isExpanded != lastBottomOffsetExpanded) {
                    lastBottomOffsetExpanded = isExpanded
                    eventListener?.onKeyboardOverlayStateChanged(isExpanded)
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

                // Parse min/max font size if specified
                val xmlMinFontSize = typedArray.getDimension(
                    R.styleable.GhosttyGLSurfaceView_minFontSize,
                    0f
                )
                val xmlMaxFontSize = typedArray.getDimension(
                    R.styleable.GhosttyGLSurfaceView_maxFontSize,
                    0f
                )

                // Parse interactive mode
                isInteractive = typedArray.getBoolean(
                    R.styleable.GhosttyGLSurfaceView_interactive,
                    true
                )

                // Apply min/max font size if specified
                if (xmlMinFontSize > 0f) {
                    minFontSize = xmlMinFontSize.coerceAtLeast(1f)
                }
                if (xmlMaxFontSize > 0f) {
                    maxFontSize = xmlMaxFontSize.coerceAtLeast(minFontSize)
                }

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
        // Clamp to configured min/max bounds
        currentFontSize = if (resolvedFontSize > 0f) {
            resolvedFontSize.coerceIn(minFontSize, maxFontSize)
        } else {
            DEFAULT_FONT_SIZE.coerceIn(minFontSize, maxFontSize)
        }
        Log.d(TAG, "Initial font size: $currentFontSize px (min: $minFontSize, max: $maxFontSize, interactive: $isInteractive)")

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
        // Always pass a valid font size (use currentFontSize which defaults to DEFAULT_FONT_SIZE)
        renderer = GhosttyRenderer(context, currentFontSize.toInt())
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
                // Preserve scroll offset only if content should scroll with overlay
                queueEvent {
                    val scrollOffset = if (shouldScrollContentWithOverlay) bottomOffset else 0f
                    renderer.setScrollPixelOffset(scrollOffset)
                }
                return true
            }

            override fun onScroll(
                e1: MotionEvent?,
                e2: MotionEvent,
                distanceX: Float,
                distanceY: Float
            ): Boolean {
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

                        // Calculate whether content should scroll during drag
                        val contentHeight = renderer.getContentHeight()
                        val visibleHeightWithKeyboard = height - maxBottomOffset
                        shouldScrollContentWithOverlay = contentHeight > visibleHeightWithKeyboard

                        Log.d(TAG, "Overlay drag: contentHeight=$contentHeight, visibleHeight=$visibleHeightWithKeyboard, shouldScroll=$shouldScrollContentWithOverlay, viewHeight=$height, maxOffset=$maxBottomOffset")

                        queueEvent {
                            val scrollOffset = if (shouldScrollContentWithOverlay) bottomOffset else 0f
                            renderer.setScrollPixelOffset(scrollOffset)
                            requestRender()
                        }
                        eventListener?.onKeyboardOverlayProgress(bottomOffset, maxBottomOffset)
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

            override fun onLongPress(e: MotionEvent) {
                if (!isInteractive) return

                // Convert touch coordinates to cell coordinates
                val cell = pixelToCell(e.x, e.y) ?: return

                Log.d(TAG, "Long press at cell (${cell.first}, ${cell.second})")

                // Start selection mode
                isSelectionMode = true
                selectionStartX = e.x
                selectionStartY = e.y

                queueEvent {
                    renderer.startSelection(cell.first, cell.second)
                    requestRender()
                }

                // Haptic feedback
                performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
            }

            override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                if (!isInteractive) return false

                // Convert touch coordinates to cell coordinates
                val cell = pixelToCell(e.x, e.y) ?: return false

                // Check for hyperlink at this cell
                queueEvent {
                    val uri = renderer.getHyperlinkAtCell(cell.first, cell.second)
                    if (uri != null) {
                        Log.d(TAG, "Hyperlink tapped: $uri")
                        post {
                            eventListener?.onHyperlinkClicked(uri)
                        }
                    }
                }

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
     * Convert pixel coordinates to cell coordinates.
     *
     * @param pixelX X coordinate in pixels
     * @param pixelY Y coordinate in pixels
     * @return Pair of (col, row) or null if out of bounds
     */
    private fun pixelToCell(pixelX: Float, pixelY: Float): Pair<Int, Int>? {
        val cellSize = renderer.getCellSize()
        val cellWidth = cellSize[0]
        val cellHeight = cellSize[1]

        if (cellWidth <= 0 || cellHeight <= 0) return null

        val col = (pixelX / cellWidth).toInt()
        val row = ((pixelY + scrollPixelOffset) / cellHeight).toInt()

        val gridSize = renderer.getGridSize()
        if (col < 0 || col >= gridSize[0] || row < 0) return null

        return Pair(col, row)
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
     * Handle touch events for scrolling and gestures.
     */
    override fun onTouchEvent(event: MotionEvent): Boolean {
        // If not interactive, don't process touch events
        if (!isInteractive) {
            return false
        }

        // Handle selection mode drag
        if (isSelectionMode && event.actionMasked == MotionEvent.ACTION_MOVE) {
            val cell = pixelToCell(event.x, event.y)
            if (cell != null) {
                queueEvent {
                    renderer.updateSelection(cell.first, cell.second)
                    requestRender()
                }
            }
            return true
        }

        // Track two-finger gestures
        handleTwoFingerGesture(event)

        // Let scroll gesture detector handle the event
        // Only process scroll if not in a two-finger gesture and not in selection mode
        val scrollHandled = if (!twoFingerGestureActive && !isSelectionMode) {
            gestureDetector.onTouchEvent(event)
        } else if (!isSelectionMode) {
            false
        } else {
            // Still process gesture detector for selection mode (for onLongPress detection)
            gestureDetector.onTouchEvent(event)
        }

        // Handle edge effect release and bottom offset snap on ACTION_UP or ACTION_CANCEL
        when (event.actionMasked) {
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                // Handle selection finalization
                if (isSelectionMode) {
                    finalizeSelection()
                    isSelectionMode = false
                }

                // Handle bottom offset snap animation
                if (maxBottomOffset > 0 && (bottomOffset > 0 || accumulatedBottomDrag != 0f)) {
                    // Snap to nearest: if past 50%, expand; otherwise collapse
                    val target = if (bottomOffset > maxBottomOffset / 2) maxBottomOffset else 0f

                    // Only scroll content if it won't fit in the visible area after keyboard
                    val contentHeight = renderer.getContentHeight()
                    val visibleHeightWithKeyboard = height - maxBottomOffset
                    shouldScrollContentWithOverlay = contentHeight > visibleHeightWithKeyboard

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

        return scrollHandled || true // Consume the event
    }

    /**
     * Finalize the current selection and notify the listener.
     */
    private fun finalizeSelection() {
        queueEvent {
            val text = renderer.getSelectionText()
            if (!text.isNullOrEmpty()) {
                Log.d(TAG, "Selection finalized: ${text.length} chars")
                post {
                    eventListener?.onTextSelected(text)
                }
            }
            renderer.clearSelection()
            requestRender()
        }
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
     * - onKeyboardOverlayProgress: during keyboard gesture drag/animation
     * - onKeyboardOverlayStateChanged: when keyboard gesture state changes
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

    // ==================== Font Size API ====================

    /**
     * Set the font size programmatically.
     *
     * The size will be clamped to the configured min/max bounds.
     * This triggers a re-render with the new font size.
     *
     * If called before the surface is ready, this also updates the pending font size
     * on the renderer, ensuring the correct size is used when the surface is created.
     *
     * @param fontSize Font size in pixels
     */
    fun setFontSize(fontSize: Float) {
        val clampedSize = fontSize.coerceIn(minFontSize, maxFontSize)
        if (kotlin.math.abs(clampedSize - currentFontSize) > 0.1f) {
            Log.i(TAG, "setFontSize: $currentFontSize -> $clampedSize px")
            currentFontSize = clampedSize

            // Update pending font size on renderer (for when surface is created)
            // This ensures correct grid size is used from the start
            renderer.setPendingFontSize(currentFontSize.toInt())

            // Also queue the font change for when surface is already ready
            queueEvent {
                renderer.setFontSize(currentFontSize.toInt())
                requestRender()
            }
        }
    }

    /**
     * Set the font size using scaled pixels (SP).
     *
     * SP values scale with the user's font size preference (accessibility).
     * The SP value is converted to pixels internally using the display metrics.
     * The resulting pixel size will be clamped to the configured min/max bounds.
     *
     * @param fontSizeSp Font size in scaled pixels (SP)
     */
    fun setFontSizeSp(fontSizeSp: Float) {
        val pixelSize = android.util.TypedValue.applyDimension(
            android.util.TypedValue.COMPLEX_UNIT_SP,
            fontSizeSp,
            context.resources.displayMetrics
        )
        Log.d(TAG, "setFontSizeSp: ${fontSizeSp}sp -> ${pixelSize}px")
        setFontSize(pixelSize)
    }

    /**
     * Get the current font size.
     *
     * @return Current font size in pixels
     */
    fun getFontSize(): Float = currentFontSize

    /**
     * Set the minimum and maximum font size bounds.
     *
     * The current font size will be re-clamped if it falls outside the new bounds.
     *
     * @param min Minimum font size in pixels (will be coerced to at least 1)
     * @param max Maximum font size in pixels (will be coerced to at least min)
     */
    fun setFontSizeBounds(min: Float, max: Float) {
        minFontSize = min.coerceAtLeast(1f)
        maxFontSize = max.coerceAtLeast(minFontSize)
        Log.d(TAG, "Font size bounds set: min=$minFontSize, max=$maxFontSize")

        // Re-clamp current font size if needed
        val clampedSize = currentFontSize.coerceIn(minFontSize, maxFontSize)
        if (clampedSize != currentFontSize) {
            setFontSize(clampedSize)
        }
    }

    /**
     * Get the minimum font size bound.
     *
     * @return Minimum font size in pixels
     */
    fun getMinFontSize(): Float = minFontSize

    /**
     * Get the maximum font size bound.
     *
     * @return Maximum font size in pixels
     */
    fun getMaxFontSize(): Float = maxFontSize

    // ==================== Interactive Mode API ====================

    /**
     * Set whether the terminal is interactive.
     *
     * When interactive is false:
     * - Touch events are not processed (scrolling, pinch-to-zoom disabled)
     * - The terminal becomes a read-only display
     *
     * Use this for preview/thumbnail modes where user interaction is not desired.
     *
     * @param interactive true to enable interaction, false to disable
     */
    fun setInteractive(interactive: Boolean) {
        if (this.isInteractive != interactive) {
            Log.d(TAG, "setInteractive: $interactive")
            this.isInteractive = interactive
        }
    }

    /**
     * Check if the terminal is interactive.
     *
     * @return true if touch events are processed, false if disabled
     */
    fun isInteractive(): Boolean = isInteractive

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
