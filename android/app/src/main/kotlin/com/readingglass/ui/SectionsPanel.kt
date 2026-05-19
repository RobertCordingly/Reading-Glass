package com.readingglass.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.readingglass.managers.SpeechManager

@Composable
fun SectionsPanel(state: DocumentState, speech: SpeechManager, onClose: () -> Unit) {
    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Sections", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Box(modifier = Modifier.weight(1f))
            IconButton(onClick = onClose) { Icon(Icons.Filled.Close, contentDescription = "Close") }
        }
        HorizontalDivider()
        if (state.sections.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize().padding(16.dp)) {
                Text(
                    "No sections detected.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else {
            LazyColumn(modifier = Modifier.fillMaxSize()) {
                items(state.sections, key = { it.id }) { section ->
                    Text(
                        text = section.title,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                speech.stop()
                                speech.cursorUtf16 = section.offset
                                speech.cursorLengthUtf16 = 0
                            }
                            .padding(
                                start = (12 + section.level * 16).dp,
                                end = 12.dp,
                                top = 8.dp,
                                bottom = 8.dp,
                            ),
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    HorizontalDivider()
                }
            }
        }
    }
}
