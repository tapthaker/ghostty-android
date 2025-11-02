/**
 * Ghostty Android OpenGL ES Renderer
 *
 * JNI interface for the Ghostty terminal renderer on Android.
 *
 * This header documents the native methods exported by the
 * libghostty_renderer.so shared library.
 */

#ifndef GHOSTTY_RENDERER_H
#define GHOSTTY_RENDERER_H

#include <jni.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Called when the library is loaded by the JVM.
 *
 * @param vm The Java VM instance
 * @param reserved Reserved for future use
 * @return The JNI version supported (JNI_VERSION_1_6)
 */
JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* reserved);

/**
 * Called when the library is unloaded by the JVM.
 *
 * @param vm The Java VM instance
 * @param reserved Reserved for future use
 */
JNIEXPORT void JNICALL JNI_OnUnload(JavaVM* vm, void* reserved);

/**
 * Called when the OpenGL surface is created.
 *
 * This is called on the GL thread when the surface is first created.
 * OpenGL context is current when this is called.
 *
 * Java signature: void nativeOnSurfaceCreated()
 */
JNIEXPORT void JNICALL
Java_com_ghostty_android_renderer_GhosttyRenderer_nativeOnSurfaceCreated(
    JNIEnv* env,
    jobject obj);

/**
 * Called when the OpenGL surface size changes.
 *
 * This is called when the surface is resized (e.g., screen rotation).
 * OpenGL context is current when this is called.
 *
 * Java signature: void nativeOnSurfaceChanged(int width, int height)
 *
 * @param width Surface width in pixels
 * @param height Surface height in pixels
 */
JNIEXPORT void JNICALL
Java_com_ghostty_android_renderer_GhosttyRenderer_nativeOnSurfaceChanged(
    JNIEnv* env,
    jobject obj,
    jint width,
    jint height);

/**
 * Called to render a frame.
 *
 * This is called on the GL thread for each frame.
 * OpenGL context is current when this is called.
 *
 * Java signature: void nativeOnDrawFrame()
 */
JNIEXPORT void JNICALL
Java_com_ghostty_android_renderer_GhosttyRenderer_nativeOnDrawFrame(
    JNIEnv* env,
    jobject obj);

/**
 * Called to destroy the renderer.
 *
 * Clean up all resources allocated by the renderer.
 * OpenGL context is current when this is called.
 *
 * Java signature: void nativeDestroy()
 */
JNIEXPORT void JNICALL
Java_com_ghostty_android_renderer_GhosttyRenderer_nativeDestroy(
    JNIEnv* env,
    jobject obj);

/**
 * Set the terminal size in character cells.
 *
 * Java signature: void nativeSetTerminalSize(int cols, int rows)
 *
 * @param cols Number of columns (character cells)
 * @param rows Number of rows (character cells)
 */
JNIEXPORT void JNICALL
Java_com_ghostty_android_renderer_GhosttyRenderer_nativeSetTerminalSize(
    JNIEnv* env,
    jobject obj,
    jint cols,
    jint rows);

#ifdef __cplusplus
}
#endif

#endif /* GHOSTTY_RENDERER_H */
