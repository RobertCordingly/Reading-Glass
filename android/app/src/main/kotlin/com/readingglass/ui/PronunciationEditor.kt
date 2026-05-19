package com.readingglass.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.readingglass.models.PronunciationEntry
import com.readingglass.store.Preferences

@Composable
fun PronunciationEditor(prefs: Preferences, onDismiss: () -> Unit) {
    val items: SnapshotStateList<PronunciationEntry> = remember {
        mutableStateListOf<PronunciationEntry>().apply { addAll(prefs.pronunciations) }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp)
            .heightIn(min = 200.dp),
    ) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Pronunciations", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            IconButton(onClick = { items.add(PronunciationEntry(find = "", replace = "")) }) {
                Icon(Icons.Filled.Add, contentDescription = "Add entry")
            }
        }
        Text(
            "Find/replace pairs applied to cleaned text before TTS speaks it.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(vertical = 4.dp),
        )
        HorizontalDivider(Modifier.padding(vertical = 8.dp))

        LazyColumn(modifier = Modifier.fillMaxWidth().heightIn(max = 400.dp)) {
            items(items, key = { it.id }) { entry ->
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    OutlinedTextField(
                        value = entry.find,
                        onValueChange = { newFind ->
                            val idx = items.indexOfFirst { it.id == entry.id }
                            if (idx >= 0) items[idx] = entry.copy(find = newFind)
                        },
                        label = { Text("Find") },
                        singleLine = true,
                        modifier = Modifier.weight(1f),
                    )
                    Spacer(Modifier.width(8.dp))
                    OutlinedTextField(
                        value = entry.replace,
                        onValueChange = { newReplace ->
                            val idx = items.indexOfFirst { it.id == entry.id }
                            if (idx >= 0) items[idx] = entry.copy(replace = newReplace)
                        },
                        label = { Text("Replace") },
                        singleLine = true,
                        modifier = Modifier.weight(1f),
                    )
                    IconButton(onClick = { items.remove(entry) }) {
                        Icon(Icons.Filled.Delete, contentDescription = "Delete")
                    }
                }
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
            horizontalArrangement = Arrangement.End,
        ) {
            TextButton(onClick = onDismiss) { Text("Cancel") }
            Spacer(Modifier.width(8.dp))
            Button(onClick = {
                prefs.setPronunciations(items.toList().filter { it.find.isNotEmpty() })
                onDismiss()
            }) { Text("Save") }
        }
    }
}
