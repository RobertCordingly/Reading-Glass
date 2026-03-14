import Foundation
import NaturalLanguage
#if os(macOS)
import AppKit
#endif

struct TextProcessorOptions {
    var skipCitations: Bool = true
    var replaceParentheses: Bool = true
    var speakGreekLetters: Bool = true
    var speakMathSymbols: Bool = true
}

enum TextProcessor {
    /// Cleans pasted text for TTS-friendly playback.
    static func process(_ input: String, options: TextProcessorOptions = TextProcessorOptions()) -> String {
        var text = input

        // 1. Fix PDF ligature Unicode characters (when they come through as Unicode)
        let ligatures: [String: String] = [
            "\u{FB00}": "ff",   // ﬀ
            "\u{FB01}": "fi",   // ﬁ
            "\u{FB02}": "fl",   // ﬂ
            "\u{FB03}": "ffi",  // ﬃ
            "\u{FB04}": "ffl",  // ﬄ
            "\u{FB05}": "st",   // ﬅ (long st)
            "\u{FB06}": "st",   // ﬆ
        ]
        for (ligature, replacement) in ligatures {
            text = text.replacingOccurrences(of: ligature, with: replacement)
        }

        // 2. Fix common PDF special characters
        let specialChars: [String: String] = [
            // Smart quotes to straight quotes
            "\u{201C}": "\"",  // left double quote "
            "\u{201D}": "\"",  // right double quote "
            "\u{2018}": "'",   // left single quote '
            "\u{2019}": "'",   // right single quote '
            // Dashes
            "\u{2013}": "-",   // en dash –
            "\u{2014}": " - ", // em dash —
            // Ellipsis
            "\u{2026}": "...", // …
            // Spaces
            "\u{00A0}": " ",   // non-breaking space
            "\u{2003}": " ",   // em space
            "\u{2002}": " ",   // en space
            "\u{2009}": " ",   // thin space
            "\u{200B}": "",    // zero-width space
            "\u{FEFF}": "",    // byte order mark
            // Hyphens
            "\u{00AD}": "",    // soft hyphen
            "\u{2010}": "-",   // hyphen
            "\u{2011}": "-",   // non-breaking hyphen
            "\u{2012}": "-",   // figure dash
            // Bullets and misc
            "\u{2022}": "-",   // bullet •
            "\u{2023}": "-",   // triangular bullet ‣
            "\u{25CF}": "-",   // black circle ●
            "\u{00B7}": " ",   // middle dot ·
            // Minus sign (math symbols handled separately below)
            "\u{2212}": "-",   // minus sign −
        ]
        for (special, replacement) in specialChars {
            text = text.replacingOccurrences(of: special, with: replacement)
        }

        // 3. Replace Greek letters with their spoken names
        if options.speakGreekLetters {
            let greek: [String: String] = [
                // Uppercase
                "\u{0391}": "Alpha", "\u{0392}": "Beta", "\u{0393}": "Gamma", "\u{0394}": "Delta",
                "\u{0395}": "Epsilon", "\u{0396}": "Zeta", "\u{0397}": "Eta", "\u{0398}": "Theta",
                "\u{0399}": "Iota", "\u{039A}": "Kappa", "\u{039B}": "Lambda", "\u{039C}": "Mu",
                "\u{039D}": "Nu", "\u{039E}": "Xi", "\u{039F}": "Omicron", "\u{03A0}": "Pi",
                "\u{03A1}": "Rho", "\u{03A3}": "Sigma", "\u{03A4}": "Tau", "\u{03A5}": "Upsilon",
                "\u{03A6}": "Phi", "\u{03A7}": "Chi", "\u{03A8}": "Psi", "\u{03A9}": "Omega",
                // Lowercase
                "\u{03B1}": "alpha", "\u{03B2}": "beta", "\u{03B3}": "gamma", "\u{03B4}": "delta",
                "\u{03B5}": "epsilon", "\u{03B6}": "zeta", "\u{03B7}": "eta", "\u{03B8}": "theta",
                "\u{03B9}": "iota", "\u{03BA}": "kappa", "\u{03BB}": "lambda", "\u{03BC}": "mu",
                "\u{03BD}": "nu", "\u{03BE}": "xi", "\u{03BF}": "omicron", "\u{03C0}": "pi",
                "\u{03C1}": "rho", "\u{03C2}": "sigma", "\u{03C3}": "sigma", "\u{03C4}": "tau",
                "\u{03C5}": "upsilon", "\u{03C6}": "phi", "\u{03C7}": "chi", "\u{03C8}": "psi",
                "\u{03C9}": "omega",
            ]
            for (letter, name) in greek {
                text = text.replacingOccurrences(of: letter, with: name)
            }
        }

        // 4. Replace arrows with spoken names
        let arrows: [String: String] = [
            "\u{2190}": " left-arrow ",    // ←
            "\u{2191}": " up-arrow ",      // ↑
            "\u{2192}": " right-arrow ",   // →
            "\u{2193}": " down-arrow ",    // ↓
            "\u{2194}": " left-right-arrow ", // ↔
            "\u{2195}": " up-down-arrow ", // ↕
            "\u{2196}": " upper-left-arrow ",  // ↖
            "\u{2197}": " upper-right-arrow ", // ↗
            "\u{2198}": " lower-right-arrow ", // ↘
            "\u{2199}": " lower-left-arrow ",  // ↙
            "\u{21D0}": " left-double-arrow ",  // ⇐
            "\u{21D1}": " up-double-arrow ",    // ⇑
            "\u{21D2}": " right-double-arrow ", // ⇒
            "\u{21D3}": " down-double-arrow ",  // ⇓
            "\u{21D4}": " left-right-double-arrow ", // ⇔
            "\u{27F5}": " long-left-arrow ",    // ⟵
            "\u{27F6}": " long-right-arrow ",   // ⟶
            "\u{27F7}": " long-left-right-arrow ", // ⟷
        ]
        for (arrow, name) in arrows {
            text = text.replacingOccurrences(of: arrow, with: name)
        }

        // 5. Replace math and logic symbols with spoken equivalents
        if options.speakMathSymbols {
        let mathSymbols: [String: String] = [
            // Operators
            "\u{00D7}": " times ",         // ×
            "\u{00F7}": " divided by ",    // ÷
            "\u{00B1}": " plus or minus ", // ±
            "\u{2212}": " minus ",         // −
            "\u{2217}": " times ",         // ∗
            "\u{2219}": " dot ",           // ∙
            "\u{22C5}": " dot ",           // ⋅
            // Comparison
            "\u{2260}": " not equal to ",  // ≠
            "\u{2264}": " less than or equal to ", // ≤
            "\u{2265}": " greater than or equal to ", // ≥
            "\u{226A}": " much less than ", // ≪
            "\u{226B}": " much greater than ", // ≫
            "\u{2248}": " approximately equal to ", // ≈
            "\u{2261}": " equivalent to ", // ≡
            "\u{221D}": " proportional to ", // ∝
            // Set theory
            "\u{2208}": " in ",            // ∈
            "\u{2209}": " not in ",        // ∉
            "\u{2282}": " subset of ",     // ⊂
            "\u{2283}": " superset of ",   // ⊃
            "\u{2286}": " subset of or equal to ", // ⊆
            "\u{2287}": " superset of or equal to ", // ⊇
            "\u{222A}": " union ",         // ∪
            "\u{2229}": " intersection ",  // ∩
            "\u{2205}": " empty set ",     // ∅
            // Logic
            "\u{2200}": " for all ",       // ∀
            "\u{2203}": " there exists ",  // ∃
            "\u{00AC}": " not ",           // ¬
            "\u{2227}": " and ",           // ∧
            "\u{2228}": " or ",            // ∨
            "\u{22A2}": " proves ",        // ⊢
            "\u{22A8}": " models ",        // ⊨
            // Calculus / analysis
            "\u{2202}": " partial ",       // ∂
            "\u{221E}": " infinity ",      // ∞
            "\u{2207}": " nabla ",         // ∇
            "\u{222B}": " integral of ",   // ∫
            "\u{2211}": " sum of ",        // ∑
            "\u{220F}": " product of ",    // ∏
            "\u{221A}": " square root of ", // √
            // Misc math
            "\u{00B0}": " degrees ",       // °
            "\u{2032}": " prime ",         // ′
            "\u{2033}": " double prime ",  // ″
            "\u{00AE}": "",                // ®
            "\u{00A9}": "",                // ©
            "\u{2122}": "",                // ™
        ]
        for (sym, name) in mathSymbols {
            text = text.replacingOccurrences(of: sym, with: name)
        }
        }

        // 6. Replace math-italic/bold Unicode letters (U+1D400-1D7FF) with plain ASCII
        //    These appear in PDFs as styled variable names like 𝐿, 𝑇, 𝑅, 𝑆, etc.
        text = replaceMathLetters(text)

        // 7. Replace subscript and superscript digits/letters with plain equivalents
        let superscripts: [Character: Character] = [
            "\u{2070}": "0", "\u{00B9}": "1", "\u{00B2}": "2", "\u{00B3}": "3",
            "\u{2074}": "4", "\u{2075}": "5", "\u{2076}": "6", "\u{2077}": "7",
            "\u{2078}": "8", "\u{2079}": "9", "\u{207A}": "+", "\u{207B}": "-",
            "\u{207C}": "=", "\u{207D}": "(", "\u{207E}": ")",
            "\u{1D2C}": "A", "\u{1D2E}": "B", "\u{1D30}": "D", "\u{1D31}": "E",
            "\u{1D33}": "G", "\u{1D34}": "H", "\u{1D35}": "I", "\u{1D36}": "J",
            "\u{1D37}": "K", "\u{1D38}": "L", "\u{1D39}": "M", "\u{1D3A}": "N",
            "\u{1D3C}": "O", "\u{1D3E}": "P", "\u{1D3F}": "R", "\u{1D40}": "T",
            "\u{1D41}": "U", "\u{1D42}": "W",
        ]
        let subscripts: [Character: Character] = [
            "\u{2080}": "0", "\u{2081}": "1", "\u{2082}": "2", "\u{2083}": "3",
            "\u{2084}": "4", "\u{2085}": "5", "\u{2086}": "6", "\u{2087}": "7",
            "\u{2088}": "8", "\u{2089}": "9", "\u{208A}": "+", "\u{208B}": "-",
            "\u{208C}": "=", "\u{208D}": "(", "\u{208E}": ")",
        ]
        text = String(text.map { superscripts[$0] ?? subscripts[$0] ?? $0 })

        // 8. Replace parentheses with commas for smoother TTS reading
        if options.replaceParentheses {
            text = text.replacingOccurrences(of: "(", with: ", ")
            text = text.replacingOccurrences(of: ")", with: ", ")
        }

        // 9. Final pass: strip any remaining non-ASCII characters that weren't handled above
        text = stripRemainingNonASCII(text)

        // 9. Remove citation brackets like [1], [2], [12], [1,2], [1-3], [1, 2, 3]
        if options.skipCitations {
            text = text.replacingOccurrences(
                of: "\\[\\d+(?:[,\\-–\\s]+\\d+)*\\]",
                with: "",
                options: .regularExpression
            )
        }

        // 10. Fix hyphenated words that span lines in PDFs (e.g. "signifi-\ncantly" -> "significantly")
        text = text.replacingOccurrences(
            of: "([a-zA-Z])-\\s*\\r?\\n\\s*([a-zA-Z])",
            with: "$1$2",
            options: .regularExpression
        )

        // 11. Remove lines that are duplicated (if a line appears more than once, remove all occurrences)
        text = removeDuplicateLines(text)

        // 12. Remove single-word lines and nonsense lines (before section marking)
        text = removeJunkLines(text)

        // 13. Mark section headers after junk removal
        text = markSectionHeaders(in: text)

        // 12. Remove newlines — replace with space
        text = text.replacingOccurrences(of: "\r\n", with: " ")
        text = text.replacingOccurrences(of: "\n", with: " ")
        text = text.replacingOccurrences(of: "\r", with: " ")
        text = text.replacingOccurrences(of: "\t", with: " ")

        // 13. Collapse multiple spaces into one
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }

        // 14. Fix broken PDF ligature words (e.g. "e$cient" -> "efficient", "#uctuations" -> "fluctuations")
        text = fixBrokenLigatures(text)

        // 15. Trim leading/trailing whitespace
        text = text.trimmingCharacters(in: .whitespaces)
        
        // 16. Replace SE Commands 
        text = text.replacingOccurrences(of: "--SE_NEWLINE--", with: "\n\n")
        text = text.replacingOccurrences(of: "--SE_SECTION--", with: "\n\n")
        
        // 17. General formatting replaces
        text = text.replacingOccurrences(of: " ,", with: ",")
        text = text.replacingOccurrences(of: " .", with: ".")
        text = text.replacingOccurrences(of: ",.", with: ".")
        text = text.replacingOccurrences(of: ":,", with: ",")
        text = text.replacingOccurrences(of: ",,", with: ",")
        
        return text
    }

    /// Removes lines that appear more than once by deleting all occurrences of duplicated lines.
    private static func removeDuplicateLines(_ text: String) -> String {
        // Split by any newline variant (\n, \r\n, \r)
        let lines = text.components(separatedBy: .newlines)
        var counts: [String: Int] = [:]
        counts.reserveCapacity(lines.count)
        for line in lines {
            counts[line, default: 0] += 1
        }
        // Keep only lines that occur exactly once
        let kept = lines.filter { (counts[$0] ?? 0) == 1 }
        return kept.joined(separator: "\n")
    }

    /// Removes lines that have fewer than 2 words or are mostly non-letter characters.
    /// Preserves SE command lines, empty lines, and blank lines.
    private static func removeJunkLines(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var kept: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Keep empty/blank lines (they become spacing)
            if trimmed.isEmpty {
                kept.append(line)
                continue
            }

            // Remove lines that are only numbers and spaces (figure axis labels)
            let strippedOfDigitsAndSpaces = trimmed.filter { !$0.isNumber && !$0.isWhitespace && $0 != "." && $0 != "," && $0 != "-" }
            if strippedOfDigitsAndSpaces.isEmpty {
                continue
            }

            // Always keep SE command markers
            if trimmed.contains("--SE_NEWLINE--") || trimmed.contains("--SE_SECTION--") {
                kept.append(line)
                continue
            }

            // Remove lines with fewer than 2 words, unless they are known section headers
            let words = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            let sectionHeaders: Set<String> = [
                "abstract", "introduction", "background", "methods", "methodology",
                "results", "discussion", "conclusion", "conclusions", "references",
                "acknowledgments", "acknowledgements", "appendix", "appendices",
                "evaluation", "overview", "motivation", "limitations", "related",
            ]
            if words.count < 2 {
                let lower = trimmed.lowercased()
                // Keep known section header words
                if words.count == 1 && sectionHeaders.contains(lower) {
                    kept.append(line)
                    continue
                }
                // Keep "Abstract—..." style headers
                if lower.hasPrefix("abstract") {
                    kept.append(line)
                    continue
                }
                continue
            }
            // Keep lines that look like roman numeral or lettered section headers
            // e.g. "I. INTRODUCTION", "A. Subsection Title"
            let romanPattern = #"^([IVXLCDM]+\.\s+.+|[A-Z]\.\s+.+)$"#
            if let romanRegex = try? NSRegularExpression(pattern: romanPattern),
               romanRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) != nil,
               words.count <= 6 {
                kept.append(line)
                continue
            }

            // Remove lines that are mostly non-letter characters (nonsense/garbage)
            let letterCount = trimmed.filter { $0.isLetter }.count
            let totalCount = trimmed.filter { !$0.isWhitespace }.count
            if totalCount > 0 && Double(letterCount) / Double(totalCount) < 0.4 {
                continue
            }

            kept.append(line)
        }

        return kept.joined(separator: "\n")
    }

    /// Detects words with non-letter characters embedded in them and tries to repair
    /// by inserting f-ligature combinations at the break point, checking against the
    /// macOS spell checker to find a valid word.
    private static func fixBrokenLigatures(_ text: String) -> String {
        #if os(macOS)
        let checker = NSSpellChecker.shared
        // Ligature replacements to try, ordered longest first so we prefer "ffi" over "fi"
        let ligatureOptions = ["ffi", "ffl", "ff", "fi", "fl"]

        // Split on whitespace, check each token individually.
        // This avoids regex word-boundary issues with non-word characters like # at the start.
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)

        for i in words.indices {
            let word = words[i]

            // Strip leading and trailing non-letter characters, preserve them to reattach later
            let leading = word.prefix(while: { !$0.isLetter })
            let trailing: Substring
            if let lastLetter = word.lastIndex(where: { $0.isLetter }) {
                trailing = word[word.index(after: lastLetter)...]
            } else {
                trailing = word[word.endIndex...]
            }
            let core = String(word[leading.endIndex..<(trailing.startIndex)])
            guard !core.isEmpty else { continue }

            // Check if the core has a non-letter, non-hyphen, non-apostrophe character in it
            let hasBreak = core.contains(where: { !$0.isLetter && $0 != "-" && $0 != "'" })
            guard hasBreak else { continue }

            // Skip if it contains numbers
            if core.rangeOfCharacter(from: .decimalDigits) != nil { continue }

            if let fixed = repairWord(core, checker: checker, ligatures: ligatureOptions) {
                words[i] = String(leading) + fixed + String(trailing)
            }
        }

        return words.joined(separator: " ")
        #else
        // NSSpellChecker is not available on iOS; return text unchanged.
        return text
        #endif
    }

    #if os(macOS)
    /// Tries to repair a single broken word by replacing each non-letter character
    /// with possible f-ligature strings and checking if the result is a real word.
    private static func repairWord(_ word: String, checker: NSSpellChecker, ligatures: [String]) -> String? {
        // Find indices of non-letter characters in the word, skipping hyphens and apostrophes
        var breakIndices: [String.Index] = []
        for idx in word.indices {
            let c = word[idx]
            if !c.isLetter && c != "-" && c != "'" {
                breakIndices.append(idx)
            }
        }

        guard !breakIndices.isEmpty else { return nil }

        // For each non-letter character, try replacing it with each ligature option
        // For simplicity, handle the common case of one break point
        // (multiple break points in one word would be very rare)
        for breakIdx in breakIndices {
            let before = String(word[word.startIndex..<breakIdx])
            let after = String(word[word.index(after: breakIdx)..<word.endIndex])

            for ligature in ligatures {
                let candidate = before + ligature + after
                let misspelledRange = checker.checkSpelling(
                    of: candidate,
                    startingAt: 0,
                    language: "en",
                    wrap: false,
                    inSpellDocumentWithTag: 0,
                    wordCount: nil
                )
                // If no misspelling found, the whole word is valid
                if misspelledRange.location == NSNotFound {
                    return candidate
                }
            }
        }

        return nil
    }
    #endif

    /// Replaces Mathematical Alphanumeric Symbols (U+1D400–U+1D7FF) with plain ASCII letters.
    /// These are styled letters used in PDFs for variables: 𝐴-𝑍, 𝑎-𝑧, 𝟎-𝟗, etc.
    private static func replaceMathLetters(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)

        for scalar in text.unicodeScalars {
            let v = scalar.value
            if let ascii = mathScalarToASCII(v) {
                result.append(ascii)
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
    
    /// Section headers
    private static func markSectionHeaders(in text: String) -> String {
        // Matches section header patterns (title must contain at least one letter):
        //   Abstract (with optional em-dash suffix like "Abstract—...")
        //   Standalone headers: REFERENCES, ACKNOWLEDGMENTS, etc.
        //   Numeric:       1 Title, 1.2 Title, 1.2.3 Title
        //   Roman numeral: I. TITLE, II. TITLE, XIV. TITLE
        //   Letter:        A. Title, B. Title
        let standaloneHeaders = [
            "Abstract", "Introduction", "Background", "Methods", "Methodology",
            "Results", "Discussion", "Conclusion", "Conclusions", "References",
            "Acknowledgments", "Acknowledgements", "Appendix", "Appendices",
            "Evaluation", "Overview", "Motivation", "Limitations", "Related Work",
            "ABSTRACT", "INTRODUCTION", "BACKGROUND", "METHODS", "METHODOLOGY",
            "RESULTS", "DISCUSSION", "CONCLUSION", "CONCLUSIONS", "REFERENCES",
            "ACKNOWLEDGMENTS", "ACKNOWLEDGEMENTS", "APPENDIX", "APPENDICES",
            "EVALUATION", "OVERVIEW", "MOTIVATION", "LIMITATIONS", "RELATED WORK",
        ]
        let standalonePattern = standaloneHeaders.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let pattern = #"^("# + standalonePattern + #"\S*.*|\d+(\.\d+)*\.?\s+(?=.*[a-zA-Z]).+|[IVXLCDM]+\.\s+(?=.*[a-zA-Z]).+|[A-Z]\.\s+(?=.*[a-zA-Z]).+)$"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        
        let lines = text.components(separatedBy: .newlines)
        var processedLines: [String] = []
        
        for line in lines {
            let range = NSRange(location: 0, length: line.utf16.count)
            if regex.firstMatch(in: line, options: [], range: range) != nil {
                processedLines.append("--SE_SECTION--\(line)--SE_SECTION--")
            } else {
                processedLines.append(line)
            }
        }
        
        return processedLines.joined(separator: "\n")
    }

    /// Maps a Unicode scalar value in the Mathematical Alphanumeric block to its ASCII equivalent.
    private static func mathScalarToASCII(_ v: UInt32) -> Character? {
        // Ranges in U+1D400–U+1D7FF for various styled letters
        let ranges: [(start: UInt32, baseChar: UInt32, count: UInt32)] = [
            // Bold A-Z
            (0x1D400, 0x41, 26), (0x1D41A, 0x61, 26),
            // Italic A-Z (note: h at 1D455 is missing, uses ℎ)
            (0x1D434, 0x41, 26), (0x1D44E, 0x61, 26),
            // Bold Italic A-Z
            (0x1D468, 0x41, 26), (0x1D482, 0x61, 26),
            // Script A-Z
            (0x1D49C, 0x41, 26), (0x1D4B6, 0x61, 26),
            // Bold Script A-Z
            (0x1D4D0, 0x41, 26), (0x1D4EA, 0x61, 26),
            // Fraktur A-Z
            (0x1D504, 0x41, 26), (0x1D51E, 0x61, 26),
            // Double-struck A-Z
            (0x1D538, 0x41, 26), (0x1D552, 0x61, 26),
            // Bold Fraktur A-Z
            (0x1D56C, 0x41, 26), (0x1D586, 0x61, 26),
            // Sans-serif A-Z
            (0x1D5A0, 0x41, 26), (0x1D5BA, 0x61, 26),
            // Sans-serif Bold A-Z
            (0x1D5D4, 0x41, 26), (0x1D5EE, 0x61, 26),
            // Sans-serif Italic A-Z
            (0x1D608, 0x41, 26), (0x1D622, 0x61, 26),
            // Sans-serif Bold Italic A-Z
            (0x1D63C, 0x41, 26), (0x1D656, 0x61, 26),
            // Monospace A-Z
            (0x1D670, 0x41, 26), (0x1D68A, 0x61, 26),
            // Bold digits 0-9
            (0x1D7CE, 0x30, 10),
            // Double-struck digits 0-9
            (0x1D7D8, 0x30, 10),
            // Sans-serif digits 0-9
            (0x1D7E2, 0x30, 10),
            // Sans-serif bold digits 0-9
            (0x1D7EC, 0x30, 10),
            // Monospace digits 0-9
            (0x1D7F6, 0x30, 10),
        ]

        for (start, baseChar, count) in ranges {
            if v >= start && v < start + count {
                return Character(UnicodeScalar(baseChar + (v - start))!)
            }
        }

        // Special case: italic h (ℎ U+210E)
        if v == 0x210E { return "h" }

        return nil
    }

    /// Scores the quality of extracted PDF text.
    /// Returns the ratio of suspicious characters (non-ASCII that aren't known good Unicode like
    /// smart quotes, em-dashes, Greek letters, math symbols, ligatures, etc.) to total characters.
    /// A high ratio (> 0.05) suggests the page has encoding issues and should be OCR'd.
    static func textQualityScore(_ text: String) -> Double {
        guard !text.isEmpty else { return 0 }

        // Characters we expect and consider "good" in PDF text
        let knownGoodRanges: [ClosedRange<UInt32>] = [
            0x0000...0x007F,   // Basic ASCII
            0x00A0...0x00FF,   // Latin-1 Supplement (accented chars, ©, ®, etc.)
            0x0100...0x024F,   // Latin Extended-A and B
            0x0370...0x03FF,   // Greek and Coptic
            0x2000...0x206F,   // General Punctuation (en-dash, em-dash, quotes, ellipsis, etc.)
            0x2070...0x209F,   // Superscripts and Subscripts
            0x20A0...0x20CF,   // Currency Symbols
            0x2100...0x214F,   // Letterlike Symbols
            0x2190...0x21FF,   // Arrows
            0x2200...0x22FF,   // Mathematical Operators
            0x2300...0x23FF,   // Miscellaneous Technical
            0x2500...0x257F,   // Box Drawing
            0x25A0...0x25FF,   // Geometric Shapes
            0x2600...0x26FF,   // Miscellaneous Symbols
            0xFB00...0xFB06,   // Alphabetic Presentation Forms (ligatures)
            0x1D400...0x1D7FF, // Mathematical Alphanumeric Symbols
        ]

        var totalChars = 0
        var suspiciousChars = 0

        for scalar in text.unicodeScalars {
            // Skip whitespace and newlines
            if scalar.properties.isWhitespace { continue }
            totalChars += 1

            let v = scalar.value
            let isKnown = knownGoodRanges.contains { $0.contains(v) }
            if !isKnown {
                suspiciousChars += 1
            }
        }

        guard totalChars > 0 else { return 0 }
        return Double(suspiciousChars) / Double(totalChars)
    }

    /// Strips any remaining non-ASCII characters, replacing them with a space
    /// (to avoid words getting merged). Preserves standard ASCII printable chars and whitespace.
    private static func stripRemainingNonASCII(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for char in text {
            if let ascii = char.asciiValue {
                result.append(char)
            } else {
                result.append(" ")
            }
        }
        return result
    }
}
