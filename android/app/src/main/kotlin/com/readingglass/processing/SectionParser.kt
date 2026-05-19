package com.readingglass.processing

import com.readingglass.models.SectionItem

/** Parses section headers from cleaned text (academic-paper layout). */
object SectionParser {
    private val STANDALONE = listOf(
        "Abstract", "Introduction", "Background", "Methods", "Methodology",
        "Results", "Discussion", "Conclusion", "Conclusions", "References",
        "Acknowledgments", "Acknowledgements", "Appendix", "Appendices",
        "Evaluation", "Overview", "Motivation", "Limitations", "Related Work",
    )

    private val patterns: List<Pair<Regex, Int>> = run {
        val alt = STANDALONE.joinToString("|") { Regex.escape(it) }
        listOf(
            Regex("""(?:^|\n\n)((?i:$alt)\S*[^\n]*)""") to 0,
            Regex("""(?:^|\n\n)([IVXLCDM]+\.\s+(?=[^\n]*[A-Za-z])[^\n]+)""") to 0,
            Regex("""(?:^|\n\n)(\d+\.?\s+(?=[^\n]*[A-Za-z])[^\n]+)""") to 0,
            Regex("""(?:^|\n\n)(\d+\.\d+[.\d]*\.?\s+(?=[^\n]*[A-Za-z])[^\n]+)""") to 1,
            Regex("""(?:^|\n\n)([A-Z]\.\s+(?=[^\n]*[A-Za-z])[^\n]+)""") to 1,
        )
    }

    fun parse(text: String): List<SectionItem> {
        if (text.isEmpty()) return emptyList()

        data class Raw(val title: String, val offset: Int, val level: Int)
        val raws = ArrayList<Raw>()

        for ((re, level) in patterns) {
            for (m in re.findAll(text)) {
                val titleRange = m.groups[1] ?: continue
                val title = titleRange.value.trim()
                if (title.length < 3 || title.startsWith("PAGE ")) continue
                raws.add(Raw(title, titleRange.range.first, level))
            }
        }
        raws.sortBy { it.offset }

        val out = ArrayList<SectionItem>(raws.size)
        var lastEnd = -1
        for (r in raws) {
            if (r.offset <= lastEnd) continue
            out.add(SectionItem(title = r.title, offset = r.offset, level = r.level))
            lastEnd = r.offset + r.title.length
        }
        return out
    }
}
