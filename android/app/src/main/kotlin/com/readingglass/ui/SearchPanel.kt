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
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.readingglass.managers.SpeechManager

@Composable
fun SearchPanel(state: DocumentState, speech: SpeechManager, onClose: () -> Unit) {
    var query by remember { mutableStateOf(state.searchQuery) }

    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Search", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Box(modifier = Modifier.weight(1f))
            IconButton(onClick = onClose) { Icon(Icons.Filled.Close, contentDescription = "Close") }
        }
        OutlinedTextField(
            value = query,
            onValueChange = {
                query = it
                state.runSearch(it)
            },
            singleLine = true,
            placeholder = { Text("Find text in document") },
            leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
        )
        HorizontalDivider()
        if (state.searchResults.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize().padding(16.dp)) {
                Text(
                    if (query.isBlank()) "Type to search." else "No results.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else {
            LazyColumn(modifier = Modifier.fillMaxSize()) {
                items(state.searchResults, key = { it.id }) { result ->
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                speech.stop()
                                speech.cursorUtf16 = result.offset
                                speech.cursorLengthUtf16 = result.length
                                state.searchJumpVersion += 1
                            }
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                    ) {
                        result.pageNumber?.let {
                            Text(
                                "Page $it",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Text(result.snippet, style = MaterialTheme.typography.bodyMedium)
                    }
                    HorizontalDivider()
                }
            }
        }
    }
}
