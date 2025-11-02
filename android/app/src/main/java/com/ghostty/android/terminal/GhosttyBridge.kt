package com.ghostty.android.terminal

import android.util.Log

/**
 * JNI bridge to libghostty-vt native library.
 * Provides access to Ghostty's VT parser and key encoding utilities.
 */
class GhosttyBridge private constructor() {

    private var keyEncoderHandle: Long = 0

    init {
        // TODO: Enable when JNI bridge is compiled
        // val success = nativeInit()
        // if (!success) {
        //     throw RuntimeException("Failed to initialize libghostty-vt")
        // }
        Log.d(TAG, "GhosttyBridge initialized (JNI disabled for now)")
    }

    /**
     * Create a key encoder for converting keyboard events to VT sequences.
     */
    fun createKeyEncoder(): Boolean {
        if (keyEncoderHandle != 0L) {
            Log.w(TAG, "Key encoder already created")
            return true
        }
        keyEncoderHandle = nativeCreateKeyEncoder()
        return keyEncoderHandle != 0L
    }

    /**
     * Destroy the key encoder.
     */
    fun destroyKeyEncoder() {
        if (keyEncoderHandle != 0L) {
            nativeDestroyKeyEncoder(keyEncoderHandle)
            keyEncoderHandle = 0
        }
    }

    /**
     * Encode a key event to a VT escape sequence.
     *
     * @param keyCode Ghostty key code
     * @param modifiers Modifier flags (shift, ctrl, alt, etc.)
     * @param text UTF-8 text representation
     * @return VT escape sequence or null if encoding failed
     */
    fun encodeKey(keyCode: Int, modifiers: Int, text: String? = null): String? {
        if (keyEncoderHandle == 0L) {
            Log.e(TAG, "Key encoder not initialized")
            return null
        }
        return nativeEncodeKey(keyEncoderHandle, keyCode, modifiers, text)
    }

    /**
     * Check if paste data is safe (doesn't contain dangerous escape sequences).
     */
    fun isPasteSafe(data: String): Boolean {
        return nativeIsPasteSafe(data)
    }

    /**
     * Get the libghostty-vt version string.
     */
    fun getVersion(): String {
        return nativeGetVersion()
    }

    fun cleanup() {
        destroyKeyEncoder()
    }

    // Native method declarations
    private external fun nativeInit(): Boolean
    private external fun nativeCreateKeyEncoder(): Long
    private external fun nativeDestroyKeyEncoder(handle: Long)
    private external fun nativeEncodeKey(
        encoderHandle: Long,
        keyCode: Int,
        modifiers: Int,
        text: String?
    ): String?
    private external fun nativeIsPasteSafe(data: String): Boolean
    private external fun nativeGetVersion(): String

    companion object {
        private const val TAG = "GhosttyBridge"

        init {
            // Load libghostty-vt.so first (dependency)
            System.loadLibrary("ghostty-vt")
            // Then load the JNI bridge library
            System.loadLibrary("ghostty_bridge")
        }

        @Volatile
        private var instance: GhosttyBridge? = null

        fun getInstance(): GhosttyBridge {
            return instance ?: synchronized(this) {
                instance ?: GhosttyBridge().also { instance = it }
            }
        }

        // Ghostty key modifier flags
        const val MOD_SHIFT = 1 shl 0
        const val MOD_CTRL = 1 shl 1
        const val MOD_ALT = 1 shl 2
        const val MOD_SUPER = 1 shl 3
        const val MOD_CAPS_LOCK = 1 shl 4
        const val MOD_NUM_LOCK = 1 shl 5
    }
}
