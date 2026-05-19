package com.readingglass.processing

/**
 * Options for [TextProcessor]. Mirrors the macOS/iPadOS implementation.
 */
data class TextProcessorOptions(
    val skipCitations: Boolean = true,
    val replaceParentheses: Boolean = true,
    val speakGreekLetters: Boolean = true,
    val speakMathSymbols: Boolean = true,
)

/**
 * Cleans pasted/extracted text for TTS-friendly playback.
 *
 * Port of `TextProcessor.swift`. The Android port omits the macOS-only
 * `NSSpellChecker`-driven broken-ligature repair; everything else matches.
 */
object TextProcessor {

    private val LIGATURES = mapOf(
        "ﬀ" to "ff",
        "ﬁ" to "fi",
        "ﬂ" to "fl",
        "ﬃ" to "ffi",
        "ﬄ" to "ffl",
        "ﬅ" to "st",
        "ﬆ" to "st",
    )

    private val SPECIAL_CHARS = mapOf(
        "“" to "\"",
        "”" to "\"",
        "‘" to "'",
        "’" to "'",
        "–" to "-",
        "—" to " - ",
        "…" to "...",
        " " to " ",
        " " to " ",
        " " to " ",
        " " to " ",
        "​" to "",
        "﻿" to "",
        "­" to "",
        "‐" to "-",
        "‑" to "-",
        "‒" to "-",
        "•" to "-",
        "‣" to "-",
        "●" to "-",
        "·" to " ",
        "−" to "-",
    )

    private val GREEK = mapOf(
        "Α" to "Alpha", "Β" to "Beta", "Γ" to "Gamma", "Δ" to "Delta",
        "Ε" to "Epsilon", "Ζ" to "Zeta", "Η" to "Eta", "Θ" to "Theta",
        "Ι" to "Iota", "Κ" to "Kappa", "Λ" to "Lambda", "Μ" to "Mu",
        "Ν" to "Nu", "Ξ" to "Xi", "Ο" to "Omicron", "Π" to "Pi",
        "Ρ" to "Rho", "Σ" to "Sigma", "Τ" to "Tau", "Υ" to "Upsilon",
        "Φ" to "Phi", "Χ" to "Chi", "Ψ" to "Psi", "Ω" to "Omega",
        "α" to "alpha", "β" to "beta", "γ" to "gamma", "δ" to "delta",
        "ε" to "epsilon", "ζ" to "zeta", "η" to "eta", "θ" to "theta",
        "ι" to "iota", "κ" to "kappa", "λ" to "lambda", "μ" to "mu",
        "ν" to "nu", "ξ" to "xi", "ο" to "omicron", "π" to "pi",
        "ρ" to "rho", "ς" to "sigma", "σ" to "sigma", "τ" to "tau",
        "υ" to "upsilon", "φ" to "phi", "χ" to "chi", "ψ" to "psi",
        "ω" to "omega",
    )

    private val ARROWS = mapOf(
        "←" to " left-arrow ",
        "↑" to " up-arrow ",
        "→" to " right-arrow ",
        "↓" to " down-arrow ",
        "↔" to " left-right-arrow ",
        "↕" to " up-down-arrow ",
        "↖" to " upper-left-arrow ",
        "↗" to " upper-right-arrow ",
        "↘" to " lower-right-arrow ",
        "↙" to " lower-left-arrow ",
        "⇐" to " left-double-arrow ",
        "⇑" to " up-double-arrow ",
        "⇒" to " right-double-arrow ",
        "⇓" to " down-double-arrow ",
        "⇔" to " left-right-double-arrow ",
        "⟵" to " long-left-arrow ",
        "⟶" to " long-right-arrow ",
        "⟷" to " long-left-right-arrow ",
    )

    private val MATH_SYMBOLS = mapOf(
        "×" to " times ", "÷" to " divided by ", "±" to " plus or minus ",
        "−" to " minus ", "∗" to " times ", "∙" to " dot ", "⋅" to " dot ",
        "≠" to " not equal to ", "≤" to " less than or equal to ",
        "≥" to " greater than or equal to ", "≪" to " much less than ",
        "≫" to " much greater than ", "≈" to " approximately equal to ",
        "≡" to " equivalent to ", "∝" to " proportional to ",
        "∈" to " in ", "∉" to " not in ",
        "⊂" to " subset of ", "⊃" to " superset of ",
        "⊆" to " subset of or equal to ", "⊇" to " superset of or equal to ",
        "∪" to " union ", "∩" to " intersection ", "∅" to " empty set ",
        "∀" to " for all ", "∃" to " there exists ",
        "¬" to " not ", "∧" to " and ", "∨" to " or ",
        "⊢" to " proves ", "⊨" to " models ",
        "∂" to " partial ", "∞" to " infinity ", "∇" to " nabla ",
        "∫" to " integral of ", "∑" to " sum of ", "∏" to " product of ",
        "√" to " square root of ",
        "°" to " degrees ", "′" to " prime ", "″" to " double prime ",
        "®" to "", "©" to "", "™" to "",
    )

    private val SUPERSCRIPTS = mapOf(
        '⁰' to '0', '¹' to '1', '²' to '2', '³' to '3',
        '⁴' to '4', '⁵' to '5', '⁶' to '6', '⁷' to '7',
        '⁸' to '8', '⁹' to '9', '⁺' to '+', '⁻' to '-',
        '⁼' to '=', '⁽' to '(', '⁾' to ')',
        'ᴬ' to 'A', 'ᴮ' to 'B', 'ᴰ' to 'D', 'ᴱ' to 'E',
        'ᴳ' to 'G', 'ᴴ' to 'H', 'ᴵ' to 'I', 'ᴶ' to 'J',
        'ᴷ' to 'K', 'ᴸ' to 'L', 'ᴹ' to 'M', 'ᴺ' to 'N',
        'ᴼ' to 'O', 'ᴾ' to 'P', 'ᴿ' to 'R', 'ᵀ' to 'T',
        'ᵁ' to 'U', 'ᵂ' to 'W',
    )

    private val SUBSCRIPTS = mapOf(
        '₀' to '0', '₁' to '1', '₂' to '2', '₃' to '3',
        '₄' to '4', '₅' to '5', '₆' to '6', '₇' to '7',
        '₈' to '8', '₉' to '9', '₊' to '+', '₋' to '-',
        '₌' to '=', '₍' to '(', '₎' to ')',
    )

    private val SECTION_WORDS = setOf(
        "abstract", "introduction", "background", "methods", "methodology",
        "results", "discussion", "conclusion", "conclusions", "references",
        "acknowledgments", "acknowledgements", "appendix", "appendices",
        "evaluation", "overview", "motivation", "limitations", "related",
    )

    private val STANDALONE_HEADERS = listOf(
        "Abstract", "Introduction", "Background", "Methods", "Methodology",
        "Results", "Discussion", "Conclusion", "Conclusions", "References",
        "Acknowledgments", "Acknowledgements", "Appendix", "Appendices",
        "Evaluation", "Overview", "Motivation", "Limitations", "Related Work",
        "ABSTRACT", "INTRODUCTION", "BACKGROUND", "METHODS", "METHODOLOGY",
        "RESULTS", "DISCUSSION", "CONCLUSION", "CONCLUSIONS", "REFERENCES",
        "ACKNOWLEDGMENTS", "ACKNOWLEDGEMENTS", "APPENDIX", "APPENDICES",
        "EVALUATION", "OVERVIEW", "MOTIVATION", "LIMITATIONS", "RELATED WORK",
    )

    private val ROMAN_LETTER_HEADER = Regex("""^([IVXLCDM]+\.\s+.+|[A-Z]\.\s+.+)$""")
    private val CITATION = Regex("""\[\d+(?:[,\-–\s]+\d+)*]""")
    private val LINE_HYPHEN = Regex("""([A-Za-z])-\s*\r?\n\s*([A-Za-z])""")
    private val SECTION_LINE = run {
        val alt = STANDALONE_HEADERS.joinToString("|") { Regex.escape(it) }
        Regex(
            "^(" +
                "(?:$alt)\\S*.*" +
                "|\\d+(?:\\.\\d+)*\\.?\\s+(?=.*[A-Za-z]).+" +
                "|[IVXLCDM]+\\.\\s+(?=.*[A-Za-z]).+" +
                "|[A-Z]\\.\\s+(?=.*[A-Za-z]).+" +
                ")$"
        )
    }

    fun process(input: String, options: TextProcessorOptions = TextProcessorOptions()): String {
        var text = input

        for ((k, v) in LIGATURES) text = text.replace(k, v)
        for ((k, v) in SPECIAL_CHARS) text = text.replace(k, v)
        if (options.speakGreekLetters) for ((k, v) in GREEK) text = text.replace(k, v)
        for ((k, v) in ARROWS) text = text.replace(k, v)
        if (options.speakMathSymbols) for ((k, v) in MATH_SYMBOLS) text = text.replace(k, v)

        text = replaceMathLetters(text)

        text = buildString(text.length) {
            for (c in text) {
                val mapped = SUPERSCRIPTS[c] ?: SUBSCRIPTS[c] ?: c
                append(mapped)
            }
        }

        if (options.replaceParentheses) {
            text = text.replace("(", ", ").replace(")", ", ")
        }

        text = stripRemainingNonAscii(text)

        if (options.skipCitations) text = text.replace(CITATION, "")

        text = text.replace(LINE_HYPHEN, "$1$2")
        text = removeDuplicateLines(text)
        text = removeJunkLines(text)
        text = markSectionHeaders(text)

        text = text.replace("\r\n", " ").replace('\n', ' ').replace('\r', ' ').replace('\t', ' ')
        while (text.contains("  ")) text = text.replace("  ", " ")

        text = text.trim()

        text = text.replace("--SE_NEWLINE--", "\n\n").replace("--SE_SECTION--", "\n\n")
        text = text.replace(" ,", ",").replace(" .", ".").replace(",.", ".")
            .replace(":,", ",").replace(",,", ",")

        return text
    }

    private fun removeDuplicateLines(text: String): String {
        val lines = text.split('\n', '\r')
        val counts = HashMap<String, Int>(lines.size)
        for (line in lines) counts[line] = (counts[line] ?: 0) + 1
        return lines.filter { (counts[it] ?: 0) == 1 }.joinToString("\n")
    }

    private fun removeJunkLines(text: String): String {
        val lines = text.split('\n')
        val kept = ArrayList<String>(lines.size)
        for (line in lines) {
            val trimmed = line.trim()
            if (trimmed.isEmpty()) { kept.add(line); continue }

            val stripped = trimmed.filter { !it.isDigit() && !it.isWhitespace() && it != '.' && it != ',' && it != '-' }
            if (stripped.isEmpty()) continue

            if (trimmed.contains("--SE_NEWLINE--") || trimmed.contains("--SE_SECTION--")) {
                kept.add(line); continue
            }

            val words = trimmed.split(Regex("\\s+")).filter { it.isNotEmpty() }
            if (words.size < 2) {
                val lower = trimmed.lowercase()
                if (words.size == 1 && lower in SECTION_WORDS) { kept.add(line); continue }
                if (lower.startsWith("abstract")) { kept.add(line); continue }
                continue
            }
            if (ROMAN_LETTER_HEADER.matches(trimmed) && words.size <= 6) {
                kept.add(line); continue
            }

            val letterCount = trimmed.count { it.isLetter() }
            val totalCount = trimmed.count { !it.isWhitespace() }
            if (totalCount > 0 && letterCount.toDouble() / totalCount < 0.4) continue

            kept.add(line)
        }
        return kept.joinToString("\n")
    }

    private fun markSectionHeaders(text: String): String {
        val lines = text.split('\n')
        val out = ArrayList<String>(lines.size)
        for (line in lines) {
            if (SECTION_LINE.matches(line)) {
                out.add("--SE_SECTION--$line--SE_SECTION--")
            } else {
                out.add(line)
            }
        }
        return out.joinToString("\n")
    }

    /**
     * Maps Mathematical Alphanumeric Symbols (U+1D400-U+1D7FF) to plain ASCII.
     * Supplementary plane code points come in as UTF-16 surrogate pairs, so this
     * walks the string by code point.
     */
    private fun replaceMathLetters(text: String): String {
        val sb = StringBuilder(text.length)
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAt(i)
            val ascii = mathScalarToAscii(cp)
            if (ascii != null) {
                sb.append(ascii)
            } else {
                sb.appendCodePoint(cp)
            }
            i += Character.charCount(cp)
        }
        return sb.toString()
    }

    private data class MathRange(val start: Int, val base: Int, val count: Int)
    private val MATH_RANGES = listOf(
        MathRange(0x1D400, 0x41, 26), MathRange(0x1D41A, 0x61, 26),
        MathRange(0x1D434, 0x41, 26), MathRange(0x1D44E, 0x61, 26),
        MathRange(0x1D468, 0x41, 26), MathRange(0x1D482, 0x61, 26),
        MathRange(0x1D49C, 0x41, 26), MathRange(0x1D4B6, 0x61, 26),
        MathRange(0x1D4D0, 0x41, 26), MathRange(0x1D4EA, 0x61, 26),
        MathRange(0x1D504, 0x41, 26), MathRange(0x1D51E, 0x61, 26),
        MathRange(0x1D538, 0x41, 26), MathRange(0x1D552, 0x61, 26),
        MathRange(0x1D56C, 0x41, 26), MathRange(0x1D586, 0x61, 26),
        MathRange(0x1D5A0, 0x41, 26), MathRange(0x1D5BA, 0x61, 26),
        MathRange(0x1D5D4, 0x41, 26), MathRange(0x1D5EE, 0x61, 26),
        MathRange(0x1D608, 0x41, 26), MathRange(0x1D622, 0x61, 26),
        MathRange(0x1D63C, 0x41, 26), MathRange(0x1D656, 0x61, 26),
        MathRange(0x1D670, 0x41, 26), MathRange(0x1D68A, 0x61, 26),
        MathRange(0x1D7CE, 0x30, 10),
        MathRange(0x1D7D8, 0x30, 10),
        MathRange(0x1D7E2, 0x30, 10),
        MathRange(0x1D7EC, 0x30, 10),
        MathRange(0x1D7F6, 0x30, 10),
    )

    private fun mathScalarToAscii(v: Int): Char? {
        for ((start, base, count) in MATH_RANGES) {
            if (v in start until start + count) return (base + (v - start)).toChar()
        }
        if (v == 0x210E) return 'h'
        return null
    }

    /**
     * Score the quality of extracted PDF text: ratio of suspicious chars to total.
     * High values (> ~0.05) suggest encoding issues and a need for OCR.
     */
    fun textQualityScore(text: String): Double {
        if (text.isEmpty()) return 0.0
        val knownGood = listOf(
            0x0000..0x007F, 0x00A0..0x00FF, 0x0100..0x024F, 0x0370..0x03FF,
            0x2000..0x206F, 0x2070..0x209F, 0x20A0..0x20CF, 0x2100..0x214F,
            0x2190..0x21FF, 0x2200..0x22FF, 0x2300..0x23FF, 0x2500..0x257F,
            0x25A0..0x25FF, 0x2600..0x26FF, 0xFB00..0xFB06, 0x1D400..0x1D7FF,
        )
        var total = 0
        var suspicious = 0
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAt(i)
            if (!Character.isWhitespace(cp)) {
                total++
                if (knownGood.none { cp in it }) suspicious++
            }
            i += Character.charCount(cp)
        }
        return if (total == 0) 0.0 else suspicious.toDouble() / total
    }

    private fun stripRemainingNonAscii(text: String): String {
        val sb = StringBuilder(text.length)
        for (c in text) {
            if (c.code <= 0x7F) sb.append(c) else sb.append(' ')
        }
        return sb.toString()
    }

    /** Apply user pronunciation overrides as plain find/replace, longest find first. */
    fun applyPronunciations(text: String, entries: List<com.readingglass.models.PronunciationEntry>): String {
        if (entries.isEmpty()) return text
        var out = text
        val sorted = entries.sortedByDescending { it.find.length }
        for (e in sorted) {
            if (e.find.isEmpty()) continue
            out = out.replace(e.find, e.replace)
        }
        return out
    }
}
