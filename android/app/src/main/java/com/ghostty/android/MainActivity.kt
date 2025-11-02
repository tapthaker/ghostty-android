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
import com.ghostty.android.terminal.GhosttyBridge
import com.ghostty.android.terminal.TerminalSession
import com.ghostty.android.ui.InputToolbar
import com.ghostty.android.ui.TerminalView
import com.ghostty.android.ui.theme.GhosttyTheme

class MainActivity : ComponentActivity() {

    private lateinit var ghosttyBridge: GhosttyBridge
    private lateinit var terminalSession: TerminalSession

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Keep screen on while terminal is active
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Initialize Ghostty bridge
        ghosttyBridge = GhosttyBridge.getInstance()
        ghosttyBridge.createKeyEncoder()

        // Create terminal session
        terminalSession = TerminalSession()

        enableEdgeToEdge()

        setContent {
            GhosttyTheme {
                TerminalScreen(
                    session = terminalSession,
                    onKeyPress = { key ->
                        terminalSession.writeInput(key)
                    }
                )
            }
        }
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
    onKeyPress: (String) -> Unit
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
        TerminalView(
            session = session,
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues),
            onTap = {
                keyboardController?.show()
            }
        )
    }
}
