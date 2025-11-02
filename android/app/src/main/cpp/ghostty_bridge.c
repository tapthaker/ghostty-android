#include <jni.h>
#include <string.h>
#include <stdlib.h>
#include <android/log.h>

// Include libghostty-vt headers
#include "ghostty/vt.h"

#define LOG_TAG "GhosttyBridge"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// JNI method: Initialize libghostty-vt
JNIEXPORT jboolean JNICALL
Java_com_ghostty_android_terminal_GhosttyBridge_nativeInit(JNIEnv *env, jobject thiz) {
    LOGD("Initializing libghostty-vt");
    // Currently libghostty-vt doesn't require global initialization
    return JNI_TRUE;
}

// JNI method: Create a key encoder
JNIEXPORT jlong JNICALL
Java_com_ghostty_android_terminal_GhosttyBridge_nativeCreateKeyEncoder(JNIEnv *env, jobject thiz) {
    GhosttyKeyEncoder encoder;
    GhosttyResult result = ghostty_key_encoder_new(NULL, &encoder);

    if (result != GHOSTTY_SUCCESS) {
        LOGE("Failed to create key encoder: %d", result);
        return 0;
    }

    LOGD("Created key encoder: %p", encoder);
    return (jlong)(uintptr_t)encoder;
}

// JNI method: Destroy key encoder
JNIEXPORT void JNICALL
Java_com_ghostty_android_terminal_GhosttyBridge_nativeDestroyKeyEncoder(JNIEnv *env, jobject thiz, jlong handle) {
    GhosttyKeyEncoder encoder = (GhosttyKeyEncoder)(uintptr_t)handle;
    if (encoder) {
        ghostty_key_encoder_free(encoder);
        LOGD("Destroyed key encoder: %p", encoder);
    }
}

// JNI method: Encode a key event to VT sequence
JNIEXPORT jstring JNICALL
Java_com_ghostty_android_terminal_GhosttyBridge_nativeEncodeKey(
    JNIEnv *env,
    jobject thiz,
    jlong encoder_handle,
    jint key_code,
    jint modifiers,
    jstring text
) {
    GhosttyKeyEncoder encoder = (GhosttyKeyEncoder)(uintptr_t)encoder_handle;
    if (!encoder) {
        LOGE("Invalid encoder handle");
        return NULL;
    }

    // Create key event
    GhosttyKeyEvent event;
    GhosttyResult result = ghostty_key_event_new(NULL, &event);
    if (result != GHOSTTY_SUCCESS) {
        LOGE("Failed to create key event");
        return NULL;
    }

    // Set key event properties
    ghostty_key_event_set_action(event, GHOSTTY_KEY_ACTION_PRESS);
    ghostty_key_event_set_key(event, (GhosttyKey)key_code);
    ghostty_key_event_set_mods(event, (GhosttyMods)modifiers);

    // Set UTF-8 text if provided
    if (text != NULL) {
        const char *utf8 = (*env)->GetStringUTFChars(env, text, NULL);
        if (utf8 != NULL) {
            ghostty_key_event_set_utf8(event, utf8, strlen(utf8));
            (*env)->ReleaseStringUTFChars(env, text, utf8);
        }
    }

    // Encode the event
    char buffer[256];
    size_t output_len = 0;
    result = ghostty_key_encoder_encode(encoder, event, buffer, sizeof(buffer), &output_len);

    ghostty_key_event_free(event);

    if (result != GHOSTTY_SUCCESS) {
        LOGE("Failed to encode key event: %d", result);
        return NULL;
    }

    if (output_len == 0) {
        return NULL;
    }

    // Create Java string from result
    jstring jresult = (*env)->NewStringUTF(env, buffer);
    LOGD("Encoded key: code=%d, mods=%d, output_len=%zu", key_code, modifiers, output_len);

    return jresult;
}

// JNI method: Check if paste data is safe
JNIEXPORT jboolean JNICALL
Java_com_ghostty_android_terminal_GhosttyBridge_nativeIsPasteSafe(
    JNIEnv *env,
    jobject thiz,
    jstring data
) {
    if (data == NULL) {
        return JNI_FALSE;
    }

    const char *utf8 = (*env)->GetStringUTFChars(env, data, NULL);
    if (utf8 == NULL) {
        return JNI_FALSE;
    }

    size_t len = strlen(utf8);
    bool is_safe = ghostty_paste_is_safe(utf8, len);

    (*env)->ReleaseStringUTFChars(env, data, utf8);

    LOGD("Paste safety check: %s", is_safe ? "safe" : "unsafe");
    return is_safe ? JNI_TRUE : JNI_FALSE;
}

// JNI method: Get library version info
JNIEXPORT jstring JNICALL
Java_com_ghostty_android_terminal_GhosttyBridge_nativeGetVersion(JNIEnv *env, jobject thiz) {
    return (*env)->NewStringUTF(env, "libghostty-vt 0.1.0");
}
