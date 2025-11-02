///! JNI Bridge Utilities
///!
///! Helper functions for working with JNI (Java Native Interface)
///! from Zig code.

const std = @import("std");
const c = @cImport({
    @cInclude("jni.h");
});

/// Convert a JNI jstring to a Zig slice
/// Caller must call releaseJString when done
pub fn getJString(
    env: *c.JNIEnv,
    jstr: c.jstring,
    buf: []u8,
) ![]const u8 {
    if (jstr == null) {
        return error.NullString;
    }

    const env_vtable = env.*.?;
    const chars = env_vtable.*.GetStringUTFChars.?(env, jstr, null);
    if (chars == null) {
        return error.GetStringFailed;
    }
    defer env_vtable.*.ReleaseStringUTFChars.?(env, jstr, chars);

    const len = env_vtable.*.GetStringUTFLength.?(env, jstr);
    if (len < 0 or len > buf.len) {
        return error.StringTooLong;
    }

    const ulen: usize = @intCast(len);
    @memcpy(buf[0..ulen], chars[0..ulen]);
    return buf[0..ulen];
}

/// Release a JNI string obtained with getJString
pub fn releaseJString(
    env: *c.JNIEnv,
    jstr: c.jstring,
    chars: [*c]const u8,
) void {
    const env_vtable = env.*.?;
    env_vtable.*.ReleaseStringUTFChars.?(env, jstr, chars);
}

/// Create a JNI jstring from a Zig slice
pub fn newJString(
    env: *c.JNIEnv,
    str: []const u8,
) !c.jstring {
    const env_vtable = env.*.?;

    // Need null-terminated string for JNI
    var buf: [1024]u8 = undefined;
    if (str.len >= buf.len) {
        return error.StringTooLong;
    }

    @memcpy(buf[0..str.len], str);
    buf[str.len] = 0;

    const jstr = env_vtable.*.NewStringUTF.?(env, @ptrCast(&buf));
    if (jstr == null) {
        return error.NewStringFailed;
    }

    return jstr;
}

/// Check if a JNI exception has occurred
pub fn checkException(env: *c.JNIEnv) bool {
    const env_vtable = env.*.?;
    const exception = env_vtable.*.ExceptionOccurred.?(env);
    return exception != null;
}

/// Clear any pending JNI exception
pub fn clearException(env: *c.JNIEnv) void {
    const env_vtable = env.*.?;
    env_vtable.*.ExceptionClear.?(env);
}

/// Print and clear any pending JNI exception
pub fn printException(env: *c.JNIEnv) void {
    const env_vtable = env.*.?;
    env_vtable.*.ExceptionDescribe.?(env);
    env_vtable.*.ExceptionClear.?(env);
}

/// Get a global reference to a Java object
pub fn newGlobalRef(env: *c.JNIEnv, obj: c.jobject) !c.jobject {
    const env_vtable = env.*.?;
    const global_ref = env_vtable.*.NewGlobalRef.?(env, obj);
    if (global_ref == null) {
        return error.NewGlobalRefFailed;
    }
    return global_ref;
}

/// Delete a global reference
pub fn deleteGlobalRef(env: *c.JNIEnv, obj: c.jobject) void {
    const env_vtable = env.*.?;
    env_vtable.*.DeleteGlobalRef.?(env, obj);
}

/// Get direct buffer address and capacity
pub fn getDirectBuffer(env: *c.JNIEnv, buf: c.jobject) !struct {
    ptr: [*]u8,
    len: usize,
} {
    const env_vtable = env.*.?;

    const addr = env_vtable.*.GetDirectBufferAddress.?(env, buf);
    if (addr == null) {
        return error.GetBufferAddressFailed;
    }

    const capacity = env_vtable.*.GetDirectBufferCapacity.?(env, buf);
    if (capacity < 0) {
        return error.GetBufferCapacityFailed;
    }

    return .{
        .ptr = @ptrCast(@alignCast(addr)),
        .len = @intCast(capacity),
    };
}

/// Create a direct ByteBuffer from a native pointer
pub fn newDirectByteBuffer(
    env: *c.JNIEnv,
    ptr: [*]u8,
    len: usize,
) !c.jobject {
    const env_vtable = env.*.?;

    const buf = env_vtable.*.NewDirectByteBuffer.?(
        env,
        @ptrCast(ptr),
        @intCast(len),
    );

    if (buf == null) {
        return error.NewDirectByteBufferFailed;
    }

    return buf;
}

/// Get byte array elements
pub fn getByteArrayElements(
    env: *c.JNIEnv,
    array: c.jbyteArray,
) !struct {
    ptr: [*]u8,
    len: usize,
    is_copy: bool,
} {
    const env_vtable = env.*.?;

    var is_copy: c.jboolean = 0;
    const elements = env_vtable.*.GetByteArrayElements.?(env, array, &is_copy);

    if (elements == null) {
        return error.GetByteArrayElementsFailed;
    }

    const len = env_vtable.*.GetArrayLength.?(env, array);
    if (len < 0) {
        return error.GetArrayLengthFailed;
    }

    return .{
        .ptr = @ptrCast(elements),
        .len = @intCast(len),
        .is_copy = is_copy != 0,
    };
}

/// Release byte array elements
pub fn releaseByteArrayElements(
    env: *c.JNIEnv,
    array: c.jbyteArray,
    elements: [*]u8,
    mode: c.jint,
) void {
    const env_vtable = env.*.?;
    env_vtable.*.ReleaseByteArrayElements.?(
        env,
        array,
        @ptrCast(elements),
        mode,
    );
}

test "JNI bridge utilities" {
    // Basic compile test - actual JNI functionality needs Android runtime
    std.testing.refAllDecls(@This());
}
