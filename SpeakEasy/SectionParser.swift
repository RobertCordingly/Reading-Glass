import Foundation

/// Parses section headers from text (e.g. academic paper structure).
enum SectionParser {
    /// Parse section headers from cleaned text. Returns sections sorted by position.
    static func parse(text: String) -> [SectionItem] {
        guard !text.isEmpty else { return [] }

        var sections: [SectionItem] = []
        let nsText = text as NSString

        let standaloneNames = [
            "Abstract", "Introduction", "Background", "Methods", "Methodology",
            "Results", "Discussion", "Conclusion", "Conclusions", "References",
            "Acknowledgments", "Acknowledgements", "Appendix", "Appendices",
            "Evaluation", "Overview", "Motivation", "Limitations", "Related Work",
        ]
        let standaloneAlt = standaloneNames.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let patterns: [(pattern: String, level: Int)] = [
            (#"(?:^|\n\n)((?i)(?:"# + standaloneAlt + #")\S*[^\n]*)"#, 0),
            (#"(?:^|\n\n)([IVXLCDM]+\.\s+(?=[^\n]*[a-zA-Z])[^\n]+)"#, 0),
            (#"(?:^|\n\n)(\d+\.?\s+(?=[^\n]*[a-zA-Z])[^\n]+)"#, 0),
            (#"(?:^|\n\n)(\d+\.\d+[\.\d]*\.?\s+(?=[^\n]*[a-zA-Z])[^\n]+)"#, 1),
            (#"(?:^|\n\n)([A-Z]\.\s+(?=[^\n]*[a-zA-Z])[^\n]+)"#, 1),
        ]

        struct RawMatch {
            let title: String
            let offset: Int
            let level: Int
        }

        var rawMatches: [RawMatch] = []

        for (pattern, level) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                let titleRange = match.range(at: 1)
                let title = nsText.substring(with: titleRange).trimmingCharacters(in: .whitespaces)
                if title.count < 3 || title.hasPrefix("PAGE ") { continue }
                rawMatches.append(RawMatch(title: title, offset: titleRange.location, level: level))
            }
        }

        rawMatches.sort { $0.offset < $1.offset }

        var lastEnd = -1
        for raw in rawMatches {
            if raw.offset <= lastEnd { continue }
            sections.append(SectionItem(title: raw.title, utf16Offset: raw.offset, level: raw.level))
            lastEnd = raw.offset + (raw.title as NSString).length
        }

        return sections
    }
}
