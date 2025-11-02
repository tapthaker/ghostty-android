package com.ghostty.android.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext

private val DarkColorScheme = darkColorScheme(
    primary = androidx.compose.ui.graphics.Color(0xFF89B4FA),
    secondary = androidx.compose.ui.graphics.Color(0xFFF5C2E7),
    tertiary = androidx.compose.ui.graphics.Color(0xFFA6E3A1),
    background = androidx.compose.ui.graphics.Color(0xFF1E1E2E),
    surface = androidx.compose.ui.graphics.Color(0xFF181825),
    onPrimary = androidx.compose.ui.graphics.Color(0xFF1E1E2E),
    onSecondary = androidx.compose.ui.graphics.Color(0xFF1E1E2E),
    onTertiary = androidx.compose.ui.graphics.Color(0xFF1E1E2E),
    onBackground = androidx.compose.ui.graphics.Color(0xFFCDD6F4),
    onSurface = androidx.compose.ui.graphics.Color(0xFFCDD6F4),
)

private val LightColorScheme = lightColorScheme(
    primary = androidx.compose.ui.graphics.Color(0xFF1E66F5),
    secondary = androidx.compose.ui.graphics.Color(0xFFEA76CB),
    tertiary = androidx.compose.ui.graphics.Color(0xFF40A02B),
    background = androidx.compose.ui.graphics.Color(0xFFEFF1F5),
    surface = androidx.compose.ui.graphics.Color(0xFFE6E9EF),
    onPrimary = androidx.compose.ui.graphics.Color.White,
    onSecondary = androidx.compose.ui.graphics.Color.White,
    onTertiary = androidx.compose.ui.graphics.Color.White,
    onBackground = androidx.compose.ui.graphics.Color(0xFF4C4F69),
    onSurface = androidx.compose.ui.graphics.Color(0xFF4C4F69),
)

@Composable
fun GhosttyTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = false,
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography,
        content = content
    )
}
