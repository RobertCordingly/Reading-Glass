package com.readingglass.ui

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.readingglass.models.SearchResult
import com.readingglass.models.SectionItem
import com.readingglass.processing.PdfBitmapSource
import com.readingglass.processing.PdfImporter
import com.readingglass.processing.SectionParser
import com.readingglass.processing.TextProcessor
import com.readingglass.processing.TextProcessorOptions
import com.readingglass.store.Preferences
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Top-level mutable document state — analogous to the @State soup at the top of
 * `ContentView.swift`. UI components read straight off this; coroutine callers
 * mutate it.
 */
class DocumentState {
    var rawText by mutableStateOf("")
    var displayText by mutableStateOf("")
    var sections = mutableStateListOf<SectionItem>()

    var pdfSource by mutableStateOf<PdfBitmapSource?>(null)
    var pageCount by mutableIntStateOf(0)

    val searchResults = mutableStateListOf<SearchResult>()
    var searchQuery by mutableStateOf("")
    /** Bumps each time a search result is clicked to drive scroll-into-view. */
    var searchJumpVersion by mutableIntStateOf(0)

    var isLoading by mutableStateOf(false)
    var errorMessage by mutableStateOf<String?>(null)

    suspend fun loadPdf(context: Context, uri: Uri, prefs: Preferences) {
        isLoading = true
        errorMessage = null
        try {
            withContext(Dispatchers.IO) {
                val extracted = PdfImporter.import(context, uri)
                    ?: throw IllegalStateException("Could not read PDF")
                val opts = TextProcessorOptions(
                    skipCitations = prefs.skipCitations,
                    replaceParentheses = prefs.replaceParentheses,
                    speakGreekLetters = prefs.speakGreekLetters,
                    speakMathSymbols = prefs.speakMathSymbols,
                )
                var cleaned = TextProcessor.process(extracted.rawText, opts)
                cleaned = TextProcessor.applyPronunciations(cleaned, prefs.pronunciations)
                val parsed = SectionParser.parse(cleaned)
                val rendered = PdfBitmapSource.fromUri(context, uri)

                withContext(Dispatchers.Main) {
                    rawText = extracted.rawText
                    displayText = cleaned
                    sections.clear(); sections.addAll(parsed)
                    pdfSource?.close()
                    pdfSource = rendered
                    pageCount = rendered?.pageCount ?: extracted.pageCount
                    searchResults.clear()
                    searchQuery = ""
                }
            }
        } catch (e: Exception) {
            errorMessage = e.message
        } finally {
            isLoading = false
        }
    }

    fun runSearch(query: String) {
        searchResults.clear()
        searchQuery = query
        if (query.isBlank() || displayText.isEmpty()) return
        val needle = query.trim()
        val haystack = displayText
        var idx = 0
        val ranges = ArrayList<IntRange>()
        while (true) {
            val found = haystack.indexOf(needle, idx, ignoreCase = true)
            if (found < 0) break
            ranges.add(found until (found + needle.length))
            idx = found + needle.length
        }

        // Map offsets to PDF pages by interpolating into the page count; accuracy
        // isn't critical for jump-into-view behavior.
        val perPageCounter = HashMap<Int, Int>()
        for (r in ranges) {
            val snippetStart = (r.first - 40).coerceAtLeast(0)
            val snippetEnd = (r.last + 40).coerceAtMost(haystack.length - 1)
            val snippet = haystack.substring(snippetStart, snippetEnd + 1)
                .replace('\n', ' ')
            val approxPage = approximatePageFor(r.first)
            val key = approxPage ?: -1
            val occurrence = (perPageCounter[key] ?: 0) + 1
            perPageCounter[key] = occurrence
            searchResults.add(
                SearchResult(
                    offset = r.first,
                    length = r.last - r.first + 1,
                    snippet = snippet,
                    pageNumber = approxPage,
                    pageOccurrence = occurrence,
                )
            )
        }
    }

    private fun approximatePageFor(offset: Int): Int? {
        if (pageCount <= 0 || displayText.isEmpty()) return null
        val ratio = offset.toDouble() / displayText.length
        return (ratio * pageCount).toInt().coerceIn(0, pageCount - 1) + 1
    }

    fun close() {
        pdfSource?.close()
        pdfSource = null
    }
}
