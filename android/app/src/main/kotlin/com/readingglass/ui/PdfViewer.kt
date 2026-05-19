package com.readingglass.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import com.readingglass.managers.SpeechManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable
fun PdfViewer(state: DocumentState, speech: SpeechManager) {
    val source = state.pdfSource
    val pageCount = state.pageCount
    val listState = rememberLazyListState()
    val cache = remember { mutableStateMapOf<Int, ImageBitmap>() }
    val density = LocalDensity.current
    val targetWidthPx = with(density) { 600.dp.toPx().toInt() }

    if (source == null || pageCount == 0) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(
                "Open a PDF to get started.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        return
    }

    val cursorOffset = speech.cursorUtf16
    // Jump to the page containing the speech cursor when it changes pages.
    val cursorPage by remember(state.displayText, pageCount) {
        derivedStateOf {
            if (state.displayText.isEmpty() || pageCount == 0) 0
            else (cursorOffset.toDouble() / state.displayText.length * pageCount).toInt().coerceIn(0, pageCount - 1)
        }
    }
    LaunchedEffect(cursorPage, state.searchJumpVersion) {
        val target = cursorPage
        if (target in 0 until pageCount) {
            listState.animateScrollToItem(target)
        }
    }

    LazyColumn(modifier = Modifier.fillMaxSize(), state = listState) {
        items((0 until pageCount).toList(), key = { it }) { index ->
            val bitmap = cache[index]
            LaunchedEffect(index) {
                if (cache[index] == null) {
                    val rendered = withContext(Dispatchers.Default) {
                        source.renderPage(index, targetWidthPx)
                    }
                    if (rendered != null) cache[index] = rendered
                }
            }
            Box(
                modifier = Modifier.fillMaxWidth().padding(8.dp),
                contentAlignment = Alignment.Center,
            ) {
                if (bitmap != null) {
                    Image(
                        bitmap = bitmap,
                        contentDescription = "Page ${index + 1}",
                        contentScale = ContentScale.FillWidth,
                        modifier = Modifier.fillMaxWidth(),
                    )
                } else {
                    Spacer(Modifier.fillMaxWidth().height(400.dp))
                }
            }
        }
    }
}
