package com.readingglass.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.readingglass.managers.SpeechManager
import com.readingglass.store.Preferences

@Composable
fun PlaybackPill(
    state: DocumentState,
    speech: SpeechManager,
    prefs: Preferences,
    onEditPronunciations: () -> Unit,
) {
    val playing = speech.isPlaying
    val sectionTitle = currentSectionTitle(state, speech.cursorUtf16)

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { speech.skipBackward(state.displayText) }) {
                Icon(Icons.Filled.SkipPrevious, contentDescription = "Previous sentence")
            }
            IconButton(onClick = {
                if (playing) speech.pause() else speech.play(state.displayText)
            }) {
                Icon(
                    if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                    contentDescription = if (playing) "Pause" else "Play"
                )
            }
            IconButton(onClick = { speech.stop() }) {
                Icon(Icons.Filled.Stop, contentDescription = "Stop")
            }
            IconButton(onClick = { speech.skipForward(state.displayText) }) {
                Icon(Icons.Filled.SkipNext, contentDescription = "Next sentence")
            }
        }
        Text(
            sectionTitle.ifEmpty { "Ready" },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 8.dp),
        )
        Spacer(Modifier.width(8.dp))
        IconButton(onClick = onEditPronunciations) {
            Icon(Icons.Filled.Edit, contentDescription = "Edit pronunciations")
        }
    }
}

private fun currentSectionTitle(state: DocumentState, cursor: Int): String {
    var current = ""
    for (s in state.sections) {
        if (s.offset <= cursor) current = s.title else break
    }
    return current
}
