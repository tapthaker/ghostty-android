package com.ghostty.android

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.viewinterop.AndroidView
import com.ghostty.android.renderer.GhosttyGLSurfaceView
import com.ghostty.android.terminal.GhosttyBridge
import com.ghostty.android.terminal.TerminalSession
import com.ghostty.android.ui.InputToolbar
import com.ghostty.android.ui.theme.GhosttyTheme

class MainActivity : ComponentActivity() {

    private lateinit var ghosttyBridge: GhosttyBridge
    private lateinit var terminalSession: TerminalSession
    private var glSurfaceView: GhosttyGLSurfaceView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Keep screen on while terminal is active
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Initialize Ghostty bridge
        ghosttyBridge = GhosttyBridge.getInstance()
        // TODO: Enable when JNI key encoder is implemented
        // ghosttyBridge.createKeyEncoder()

        // Create terminal session
        terminalSession = TerminalSession()

        enableEdgeToEdge()

        setContent {
            GhosttyTheme {
                TerminalScreen(
                    session = terminalSession,
                    onKeyPress = { key ->
                        terminalSession.writeInput(key)
                    },
                    onGLSurfaceViewCreated = { view ->
                        glSurfaceView = view
                    }
                )
            }
        }
    }

    override fun onPause() {
        super.onPause()
        // Pause the GL rendering thread
        glSurfaceView?.onPauseView()
    }

    override fun onResume() {
        super.onResume()
        // Resume the GL rendering thread
        glSurfaceView?.onResumeView()
    }

    override fun onDestroy() {
        super.onDestroy()
        terminalSession.stop()
        ghosttyBridge.cleanup()
    }
}

@Composable
fun TerminalScreen(
    session: TerminalSession,
    onKeyPress: (String) -> Unit,
    onGLSurfaceViewCreated: (GhosttyGLSurfaceView) -> Unit
) {
    val keyboardController = LocalSoftwareKeyboardController.current
    val focusManager = LocalFocusManager.current

    Scaffold(
        bottomBar = {
            InputToolbar(
                onKeyPress = onKeyPress,
                onShowKeyboard = {
                    keyboardController?.show()
                }
            )
        }
    ) { paddingValues ->
        // Use AndroidView to embed the native OpenGL surface view
        AndroidView(
            factory = { context ->
                GhosttyGLSurfaceView(context).also { view ->
                    // Notify the activity that the view has been created
                    onGLSurfaceViewCreated(view)

                    // Set up terminal size (will be calculated based on view size)
                    // For now, use default terminal size
                    view.setTerminalSize(80, 24)
                }
            },
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        )
    }
}
