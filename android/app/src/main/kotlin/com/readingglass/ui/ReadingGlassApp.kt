package com.readingglass.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.weight
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FolderOpen
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.ViewList
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.readingglass.managers.SpeechManager
import com.readingglass.store.Preferences
import kotlinx.coroutines.launch

private enum class Panel { Reader, Search, Sections }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReadingGlassApp() {
    val context = LocalContext.current
    val prefs = remember { Preferences.get(context) }
    val speech = remember { SpeechManager(context) }
    val state = remember { DocumentState() }
    val scope = rememberCoroutineScope()

    var panel by remember { mutableStateOf(Panel.Reader) }
    var showOptions by remember { mutableStateOf(false) }
    var showPronunciations by remember { mutableStateOf(false) }

    val pickPdf = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null) {
            scope.launch {
                speech.stop()
                state.loadPdf(context, uri, prefs)
                speech.resetCursor()
            }
        }
    }

    LaunchedEffect(prefs.voiceName) { if (prefs.voiceName.isNotEmpty()) speech.setVoice(prefs.voiceName) }
    LaunchedEffect(prefs.speedMultiplier) { speech.setRate(prefs.speedMultiplier) }
    LaunchedEffect(Unit) { speech.setRate(prefs.speedMultiplier) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text("Reading Glass", fontWeight = FontWeight.SemiBold)
                },
                actions = {
                    IconButton(onClick = { pickPdf.launch(arrayOf("application/pdf")) }) {
                        Icon(Icons.Filled.FolderOpen, contentDescription = "Open PDF")
                    }
                    IconButton(onClick = { panel = Panel.Sections }) {
                        Icon(Icons.Filled.ViewList, contentDescription = "Sections")
                    }
                    IconButton(onClick = { panel = Panel.Search }) {
                        Icon(Icons.Filled.Search, contentDescription = "Search")
                    }
                    IconButton(onClick = { showOptions = true }) {
                        Icon(Icons.Filled.Settings, contentDescription = "Options")
                    }
                }
            )
        }
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            if (state.isLoading) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(12.dp)) {
                    CircularProgressIndicator(modifier = Modifier.width(20.dp).height(20.dp), strokeWidth = 2.dp)
                    Spacer(Modifier.width(8.dp))
                    Text("Loading PDF…", style = MaterialTheme.typography.bodyMedium)
                }
            }
            state.errorMessage?.let { msg ->
                Text(
                    msg,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp)
                )
            }

            Row(modifier = Modifier.weight(1f).fillMaxWidth()) {
                Box(modifier = Modifier.weight(1.2f).fillMaxSize()) {
                    PdfViewer(state = state, speech = speech)
                }
                HorizontalDivider(modifier = Modifier.width(1.dp).fillMaxSize())
                Box(modifier = Modifier.weight(1f).fillMaxSize()) {
                    when (panel) {
                        Panel.Reader -> ReaderText(state = state, speech = speech)
                        Panel.Sections -> SectionsPanel(state = state, speech = speech) { panel = Panel.Reader }
                        Panel.Search -> SearchPanel(state = state, speech = speech) { panel = Panel.Reader }
                    }
                }
            }

            HorizontalDivider()
            PlaybackPill(
                state = state,
                speech = speech,
                prefs = prefs,
                onEditPronunciations = { showPronunciations = true },
            )
        }
    }

    if (showOptions) {
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(onDismissRequest = { showOptions = false }, sheetState = sheetState) {
            OptionsSheet(prefs = prefs, speech = speech) { showOptions = false }
        }
    }

    if (showPronunciations) {
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(onDismissRequest = { showPronunciations = false }, sheetState = sheetState) {
            PronunciationEditor(prefs = prefs) { showPronunciations = false }
        }
    }
}
