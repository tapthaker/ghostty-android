package com.ghostty.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.rememberScrollableState
import androidx.compose.foundation.gestures.scrollable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ghostty.android.terminal.TerminalSession

/**
 * Composable function that displays a terminal view.
 */
@Composable
fun TerminalView(
    session: TerminalSession,
    modifier: Modifier = Modifier,
    onTap: (() -> Unit)? = null
) {
    val output by session.output.collectAsState()
    val scrollState = rememberScrollState()

    DisposableEffect(Unit) {
        session.start()
        onDispose {
            session.stop()
        }
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(TerminalColors.Background)
            .pointerInput(Unit) {
                detectTapGestures(
                    onTap = { onTap?.invoke() }
                )
            }
    ) {
        BasicText(
            text = output,
            style = TextStyle(
                fontFamily = FontFamily.Monospace,
                fontSize = 14.sp,
                color = TerminalColors.Foreground,
                lineHeight = 18.sp
            ),
            modifier = Modifier
                .fillMaxSize()
                .padding(8.dp)
                .verticalScroll(scrollState)
        )
    }
}

/**
 * Terminal color scheme.
 */
object TerminalColors {
    val Background = Color(0xFF1E1E2E)
    val Foreground = Color(0xFFCDD6F4)
    val Cursor = Color(0xFFF5E0DC)

    // ANSI colors (basic 16-color palette)
    val Black = Color(0xFF45475A)
    val Red = Color(0xFFF38BA8)
    val Green = Color(0xFFA6E3A1)
    val Yellow = Color(0xFFF9E2AF)
    val Blue = Color(0xFF89B4FA)
    val Magenta = Color(0xFFF5C2E7)
    val Cyan = Color(0xFF94E2D5)
    val White = Color(0xFFBAC2DE)

    val BrightBlack = Color(0xFF585B70)
    val BrightRed = Color(0xFFF38BA8)
    val BrightGreen = Color(0xFFA6E3A1)
    val BrightYellow = Color(0xFFF9E2AF)
    val BrightBlue = Color(0xFF89B4FA)
    val BrightMagenta = Color(0xFFF5C2E7)
    val BrightCyan = Color(0xFF94E2D5)
    val BrightWhite = Color(0xFFA6ADC8)
}
