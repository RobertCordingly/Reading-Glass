package com.readingglass.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
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
import com.readingglass.store.Preferences

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OptionsSheet(prefs: Preferences, speech: SpeechManager, onDismiss: () -> Unit) {
    val voices = speech.availableVoices
    var voiceMenuExpanded by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(16.dp)
    ) {
        Text("Options", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.padding(top = 12.dp))

        Text("Voice", style = MaterialTheme.typography.titleSmall)
        ExposedDropdownMenuBox(
            expanded = voiceMenuExpanded,
            onExpandedChange = { voiceMenuExpanded = it }
        ) {
            OutlinedTextField(
                value = prefs.voiceName.ifEmpty { "(default)" },
                onValueChange = {},
                readOnly = true,
                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = voiceMenuExpanded) },
                modifier = Modifier.fillMaxWidth().menuAnchor(),
            )
            androidx.compose.material3.ExposedDropdownMenu(
                expanded = voiceMenuExpanded,
                onDismissRequest = { voiceMenuExpanded = false }
            ) {
                voices.forEach { v ->
                    DropdownMenuItem(
                        text = { Text("${v.name} (${v.locale})") },
                        onClick = {
                            prefs.setVoice(v.name)
                            speech.setVoice(v.name)
                            voiceMenuExpanded = false
                        }
                    )
                }
            }
        }

        Spacer(Modifier.padding(top = 12.dp))
        Text("Speed: ${"%.1f".format(prefs.speedMultiplier)}x", style = MaterialTheme.typography.titleSmall)
        Slider(
            value = prefs.speedMultiplier,
            onValueChange = { prefs.setSpeed(it); speech.setRate(it) },
            valueRange = 0.5f..4.0f,
            steps = 6,
        )

        HorizontalDivider(Modifier.padding(vertical = 12.dp))
        Text("Text Processing", style = MaterialTheme.typography.titleSmall)
        ToggleRow("Skip citations like [1]", prefs.skipCitations) { prefs.skipCitations = it; prefs.persistBooleans() }
        ToggleRow("Replace parentheses with commas", prefs.replaceParentheses) { prefs.replaceParentheses = it; prefs.persistBooleans() }
        ToggleRow("Speak Greek letters", prefs.speakGreekLetters) { prefs.speakGreekLetters = it; prefs.persistBooleans() }
        ToggleRow("Speak math symbols", prefs.speakMathSymbols) { prefs.speakMathSymbols = it; prefs.persistBooleans() }
        ToggleRow("Skip text before Abstract", prefs.ignoreBeforeAbstract) { prefs.ignoreBeforeAbstract = it; prefs.persistBooleans() }
        ToggleRow("Skip References", prefs.ignoreReferences) { prefs.ignoreReferences = it; prefs.persistBooleans() }

        Spacer(Modifier.padding(top = 12.dp))
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            Button(onClick = onDismiss) { Text("Done") }
        }
    }
}

@Composable
private fun ToggleRow(label: String, value: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, modifier = Modifier.weight(1f))
        Spacer(Modifier.width(8.dp))
        Switch(checked = value, onCheckedChange = onChange)
    }
}
