package com.readingglass.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.readingglass.managers.SpeechManager

/**
 * Reader pane: renders the cleaned text with the currently-spoken word
 * highlighted. Tapping a word seeks the speech cursor to that offset.
 */
@Composable
fun ReaderText(state: DocumentState, speech: SpeechManager) {
    val text = state.displayText
    val cursor = speech.cursorUtf16
    val cursorLen = speech.cursorLengthUtf16
    val scrollState = rememberScrollState()

    var layout by remember { mutableStateOf<TextLayoutResult?>(null) }
    val highlightColor = MaterialTheme.colorScheme.primaryContainer
    val highlightFg = MaterialTheme.colorScheme.onPrimaryContainer

    val annotated = remember(text, cursor, cursorLen, highlightColor, highlightFg) {
        if (text.isEmpty()) AnnotatedString("")
        else buildAnnotatedString {
            val range = speech.highlightRange(text)
            if (range == null) {
                append(text)
            } else {
                append(text.substring(0, range.first))
                pushStyle(SpanStyle(background = highlightColor, color = highlightFg, fontWeight = FontWeight.SemiBold))
                append(text.substring(range.first, range.last + 1))
                pop()
                if (range.last + 1 < text.length) append(text.substring(range.last + 1))
            }
        }
    }

    // Auto-scroll to keep the highlighted word in view.
    val density = LocalDensity.current
    LaunchedEffect(cursor) {
        val l = layout ?: return@LaunchedEffect
        if (text.isEmpty()) return@LaunchedEffect
        val safe = cursor.coerceIn(0, (text.length - 1).coerceAtLeast(0))
        val box = l.getBoundingBox(safe)
        val target = (box.top - 80f).coerceAtLeast(0f).toInt()
        val threshold = with(density) { 80.dp.toPx() }
        if (kotlin.math.abs(target - scrollState.value).toFloat() > threshold) {
            scrollState.animateScrollTo(target)
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surface)
            .verticalScroll(scrollState)
            .padding(16.dp)
            .pointerInput(text, layout) {
                detectTapGestures { offset ->
                    val l = layout ?: return@detectTapGestures
                    val pos = l.getOffsetForPosition(offset)
                    if (pos in text.indices) {
                        speech.stop()
                        // Snap back to the start of the tapped word.
                        var s = pos
                        while (s > 0 && !text[s - 1].isWhitespace()) s--
                        speech.cursorUtf16 = s
                        speech.cursorLengthUtf16 = 0
                    }
                }
            }
    ) {
        if (text.isEmpty()) {
            Text(
                "No document loaded.",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        } else {
            Text(
                text = annotated,
                style = MaterialTheme.typography.bodyLarge.copy(fontSize = 18.sp, lineHeight = 28.sp),
                onTextLayout = { layout = it },
                color = MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}
