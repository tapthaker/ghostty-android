# ProGuard rules for consumers of the terminal-library

# Keep JNI native methods
-keepclasseswithmembernames class com.ghostty.android.renderer.GhosttyRenderer {
    native <methods>;
}
-keepclasseswithmembernames class com.ghostty.android.terminal.GhosttyBridge {
    native <methods>;
}

# Keep classes that load native libraries
-keep class com.ghostty.android.renderer.GhosttyRenderer { *; }
-keep class com.ghostty.android.renderer.GhosttyGLSurfaceView { *; }
-keep class com.ghostty.android.terminal.GhosttyBridge { *; }
-keep class com.ghostty.android.terminal.TerminalSession { *; }
