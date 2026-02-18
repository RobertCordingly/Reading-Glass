import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Handles PDF import and text extraction.
enum PDFImportProcessor {
    /// Opens the system file picker and imports a PDF. Returns document and raw extracted text, or nil if cancelled.
    static func importDocument() -> (document: PDFDocument, rawText: String)? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.message = "Select a PDF to import"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let document = PDFDocument(url: url) else { return nil }

        let rawText = extractText(from: document)
        return (document, rawText)
    }

    /// Assembles extracted text with PAGE markers from a PDF document.
    static func extractText(from document: PDFDocument) -> String {
        var pageTexts: [Int: String] = [:]
        for i in 0..<document.pageCount {
            pageTexts[i] = document.page(at: i)?.string ?? ""
        }
        return assembleExtractedText(document: document, pageTexts: pageTexts)
    }

    /// Assembles the final extracted text with PAGE markers from per-page text.
    private static func assembleExtractedText(document: PDFDocument, pageTexts: [Int: String]) -> String {
        var result = ""
        for i in 0..<document.pageCount {
            result += "--SE_NEWLINE--PAGE \(i)--SE_NEWLINE--\n"
            if let text = pageTexts[i] {
                result += text + "\n"
            }
        }
        return result
    }
}
