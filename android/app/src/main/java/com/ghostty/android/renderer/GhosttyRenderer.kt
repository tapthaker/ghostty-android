package com.ghostty.android.renderer

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
class GhosttyRenderer : GLSurfaceView.Renderer {

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
    private external fun nativeOnSurfaceChanged(width: Int, height: Int)
    private external fun nativeOnDrawFrame()
    private external fun nativeDestroy()
    private external fun nativeSetTerminalSize(cols: Int, rows: Int)

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
        Log.d(TAG, "onSurfaceChanged: ${width}x${height}")

        try {
            nativeOnSurfaceChanged(width, height)
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
}
