package com.ghostty.android.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * Toolbar for terminal input with common keys and actions.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InputToolbar(
    onKeyPress: (String) -> Unit,
    onShowKeyboard: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surfaceVariant,
        tonalElevation = 3.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 4.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Common terminal keys
            Row(
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                ToolbarButton("ESC", onClick = { onKeyPress("\u001B") })
                ToolbarButton("TAB", onClick = { onKeyPress("\t") })
                ToolbarButton("CTRL", onClick = { /* TODO: Implement modifier state */ })
                ToolbarButton("ALT", onClick = { /* TODO: Implement modifier state */ })
                ToolbarButton("↑", onClick = { onKeyPress("\u001B[A") })
                ToolbarButton("↓", onClick = { onKeyPress("\u001B[B") })
            }

            // Keyboard button
            FilledTonalIconButton(
                onClick = onShowKeyboard,
                modifier = Modifier.size(36.dp)
            ) {
                Icon(
                    Icons.Default.KeyboardAlt,
                    contentDescription = "Show keyboard"
                )
            }
        }
    }
}

@Composable
private fun ToolbarButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    OutlinedButton(
        onClick = onClick,
        modifier = modifier.height(36.dp),
        contentPadding = PaddingValues(horizontal = 8.dp)
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelSmall
        )
    }
}
