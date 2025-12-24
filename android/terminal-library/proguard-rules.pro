# ProGuard rules for terminal-library

# Keep JNI native methods - these are called from native code
-keepclasseswithmembernames class com.ghostty.android.renderer.GhosttyRenderer {
    native <methods>;
}
-keepclasseswithmembernames class com.ghostty.android.terminal.GhosttyBridge {
    native <methods>;
}

# Keep public API classes
-keep public class com.ghostty.android.renderer.* { public *; }
-keep public class com.ghostty.android.terminal.* { public *; }
-keep public class com.ghostty.android.testing.* { public *; }
