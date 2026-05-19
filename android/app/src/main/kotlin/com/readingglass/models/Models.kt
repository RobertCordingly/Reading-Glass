package com.readingglass.models

import kotlinx.serialization.Serializable
import java.util.UUID

enum class SidebarMode { Hidden, Reader, Search, Sections }

/** A single search result with its location and a text snippet for display. */
data class SearchResult(
    val id: String = UUID.randomUUID().toString(),
    /** UTF-16 offset into the full displayed text. */
    val offset: Int,
    val length: Int,
    val snippet: String,
    /** 1-based PDF page number, or null if not resolvable. */
    val pageNumber: Int?,
    /** 1-based ordinal of this match among matches on the same page. */
    val pageOccurrence: Int,
)

/** A section header parsed out of the cleaned text. */
data class SectionItem(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val offset: Int,
    val level: Int,
)

/** A pronunciation mapping: find text and replace with spoken form. */
@Serializable
data class PronunciationEntry(
    val id: String = UUID.randomUUID().toString(),
    val find: String,
    val replace: String,
)
