#if os(iOS)
import PDFKit

/// iOS equivalent of PDFImportProcessor.
/// File picking is handled via .fileImporter in ContentView; this provides the shared extraction logic.
enum PDFImportProcessor {
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
#endif
