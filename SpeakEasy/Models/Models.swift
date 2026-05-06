import Foundation
import SwiftUI

enum SidebarMode {
    case hidden
    case reader
    case editor
    case search
    case sections
}

/// A single search result with its location and a text snippet for display.
struct SearchResult: Identifiable {
    let id = UUID()
    let range: NSRange
    let snippet: String
    /// 1-based PDF page number this match falls on, if it could be resolved from
    /// the document's PAGE markers. `nil` for non-PDF text.
    let pageNumber: Int?
    /// 1-based ordinal of this match among matches on the same page, in document
    /// order. Used to align with the PDF's own findString results when drawing a
    /// highlight rectangle on the page thumbnail. 0 when no page mapping exists.
    let pageOccurrence: Int
}

/// A pronunciation mapping: find text and replace with spoken form.
struct PronunciationEntry: Identifiable, Codable {
    var id = UUID()
    var find: String
    var replace: String
}

/// A log entry for AI cleanup of a chunk.
struct CleanupLogEntry: Identifiable {
    let id = UUID()
    let chunkIndex: Int
    let sectionTitle: String
    let beforeText: String
    let afterText: String
    let originalLength: Int
    let cleanedLength: Int
    var charsRemoved: Int { originalLength - cleanedLength }
}
