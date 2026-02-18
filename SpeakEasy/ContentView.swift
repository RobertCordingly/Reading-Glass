import PDFKit
import AppKit
import SwiftUI
import FoundationModels

/// Wraps PDFKit's PDFThumbnailView, linked to a PDFView instance.
struct PDFThumbnailStrip: NSViewRepresentable {
    let pdfView: PDFView?

    func makeNSView(context: Context) -> PDFThumbnailView {
        let thumbnailView = PDFThumbnailView()
        thumbnailView.thumbnailSize = CGSize(width: 120, height: 165)
        thumbnailView.pdfView = pdfView
        if let scrollView = thumbnailView.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView {
            scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        }
        thumbnailView.enclosingScrollView?.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        return thumbnailView
    }

    func updateNSView(_ thumbnailView: PDFThumbnailView, context: Context) {
        if thumbnailView.pdfView !== pdfView {
            thumbnailView.pdfView = pdfView
        }
    }
}

/// A macOS toolbar-friendly NSSearchField wrapper.
struct ToolbarSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField(string: text)
        field.placeholderString = prompt
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit)
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = false
        field.sendsWholeSearchString = false
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = prompt
        context.coordinator.onSubmit = onSubmit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding var text: String
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            text = field.stringValue
        }

        @objc func submit() {
            onSubmit()
        }
    }
}

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument?
    let highlightText: String
    let highlightPage: Int?
    let onWordSelected: (String, Int, Int) -> Void  // (word, pageIndex, occurrence)
    let onPDFViewReady: (PDFView) -> Void

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.document = document
        pdfView.pageOverlayViewProvider = context.coordinator

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: .PDFViewSelectionChanged,
            object: pdfView
        )

        DispatchQueue.main.async {
            onPDFViewReady(pdfView)
        }

        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
        context.coordinator.onWordSelected = onWordSelected

        highlightInPDF(pdfView, context: context)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onWordSelected: onWordSelected)
    }

    private func highlightInPDF(_ pdfView: PDFView, context: Context) {
        guard let document = pdfView.document, !highlightText.isEmpty else {
            context.coordinator.currentHighlightMatch = nil
            context.coordinator.repositionGlassOverlay(in: pdfView)
            return
        }

        let matches = document.findString(highlightText, withOptions: .caseInsensitive)
        guard !matches.isEmpty else { return }

        // Prefer matches on the target page, then fall back to nearest page
        let bestMatch: PDFSelection?
        if let targetPage = highlightPage {
            let pageMatches = matches.filter { match in
                match.pages.first.map { document.index(for: $0) } == targetPage
            }
            bestMatch = pageMatches.first
                ?? findBestMatchByPage(matches, nearPage: targetPage, in: document)
        } else {
            bestMatch = findBestMatchByPage(
                matches,
                nearPage: context.coordinator.lastPDFPage.map { document.index(for: $0) },
                in: document
            )
        }

        guard let match = bestMatch else { return }

        // --- Jump stabilization (skipped for manual clicks) ---
        let coord = context.coordinator
        if coord.bypassStabilization {
            coord.bypassStabilization = false
            coord.pendingMatch = nil
            coord.pendingMatchCount = 0
        } else if let currentMatch = coord.currentHighlightMatch,
           let currentPage = currentMatch.pages.first,
           let newPage = match.pages.first,
           let doc = pdfView.document {

            let currentPageIdx = doc.index(for: currentPage)
            let newPageIdx = doc.index(for: newPage)
            let pageDelta = abs(newPageIdx - currentPageIdx)

            let isFarJump: Bool = {
                if pageDelta >= 1 { return true }
                let currentY = currentMatch.bounds(for: currentPage).midY
                let newY = match.bounds(for: newPage).midY
                return abs(currentY - newY) > 150
            }()

            if isFarJump {
                // Use higher threshold for multi-page jumps, lower for short jumps
                let threshold = pageDelta > 1
                    ? Coordinator.longJumpThreshold
                    : Coordinator.shortJumpThreshold

                if let pending = coord.pendingMatch,
                   let pendingPage = pending.pages.first,
                   let matchPage = match.pages.first,
                   pendingPage === matchPage,
                   abs(pending.bounds(for: pendingPage).midY - match.bounds(for: matchPage).midY) < 100 {
                    coord.pendingMatchCount += 1
                } else {
                    coord.pendingMatch = match
                    coord.pendingMatchCount = 1
                }

                if coord.pendingMatchCount < threshold {
                    coord.repositionGlassOverlay(in: pdfView)
                    return
                }
                coord.pendingMatch = nil
                coord.pendingMatchCount = 0
            } else {
                coord.pendingMatch = nil
                coord.pendingMatchCount = 0
            }
        }

        coord.lastPDFPage = match.pages.first
        coord.currentHighlightMatch = match

        // Only scroll if the match is not already visible on screen
        if let page = match.pages.first {
            let pageBounds = match.bounds(for: page)
            let viewRect = pdfView.convert(pageBounds, from: page)
            let visibleRect = pdfView.bounds.insetBy(dx: 0, dy: 40)

            if !visibleRect.contains(viewRect) {
                let viewHeight = pdfView.bounds.height
                let offsetPoints = viewHeight * 0.33
                let scaleFactor = pdfView.scaleFactor
                let pageOffset = offsetPoints / scaleFactor
                let destY = pageBounds.maxY + pageOffset

                let dest = PDFDestination(page: page, at: CGPoint(x: pageBounds.origin.x, y: destY))
                pdfView.go(to: dest)
            }
        }

        // Setup scroll/zoom tracking and position the glass overlay
        coord.setupScrollTracking(for: pdfView)
        coord.repositionGlassOverlay(in: pdfView)
    }

    /// Finds the match on the closest page to the target.
    private func findBestMatchByPage(_ matches: [PDFSelection], nearPage targetPage: Int?, in document: PDFDocument) -> PDFSelection? {
        guard !matches.isEmpty else { return nil }
        guard let targetPage = targetPage else { return matches.first }

        var bestMatch = matches.first!
        var bestDistance = Int.max

        for match in matches {
            guard let matchPage = match.pages.first else { continue }
            let matchPageIndex = document.index(for: matchPage)

            let distance = matchPageIndex - targetPage
            let adjustedDistance = distance >= 0 ? distance : distance + 10000
            if adjustedDistance < bestDistance {
                bestDistance = adjustedDistance
                bestMatch = match
            }
        }

        return bestMatch
    }

    class Coordinator: NSObject, PDFPageOverlayViewProvider {
        var onWordSelected: (String, Int, Int) -> Void
        var lastPDFPage: PDFPage?

        // Glass highlight overlay
        var glassOverlay: NSView?
        var currentHighlightMatch: PDFSelection?
        private var scrollObserver: NSObjectProtocol?

        // Sticky page number overlay
        var pageNumberOverlay: NSHostingView<AnyView>?
        var currentVisiblePage: Int = -1

        // Jump stabilization: require consecutive "votes" before jumping far
        var pendingMatch: PDFSelection?
        var pendingMatchCount: Int = 0
        static let shortJumpThreshold = 3   // same page or 1 page away
        static let longJumpThreshold = 10   // more than 1 page away
        var bypassStabilization = false  // set true on manual clicks to skip buffering
        private var zoomObserver: NSObjectProtocol?

        init(onWordSelected: @escaping (String, Int, Int) -> Void) {
            self.onWordSelected = onWordSelected
        }

        deinit {
            if let obs = scrollObserver { NotificationCenter.default.removeObserver(obs) }
            if let obs = zoomObserver { NotificationCenter.default.removeObserver(obs) }
        }

        // MARK: - Glass Highlight Overlay

        func setupScrollTracking(for pdfView: PDFView) {
            guard scrollObserver == nil else { return }

            // Find the internal clip view for scroll tracking
            func findClipView(_ view: NSView) -> NSClipView? {
                if let cv = view as? NSClipView { return cv }
                for sub in view.subviews {
                    if let cv = findClipView(sub) { return cv }
                }
                return nil
            }

            if let clipView = findClipView(pdfView) {
                clipView.postsBoundsChangedNotifications = true
                scrollObserver = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: clipView,
                    queue: .main
                ) { [weak self, weak pdfView] _ in
                    guard let self, let pdfView else { return }
                    self.repositionGlassOverlay(in: pdfView)
                    self.updatePageNumberOverlay(in: pdfView)
                }
            }

            // Track zoom changes
            zoomObserver = NotificationCenter.default.addObserver(
                forName: .PDFViewScaleChanged,
                object: pdfView,
                queue: .main
            ) { [weak self, weak pdfView] _ in
                guard let self, let pdfView else { return }
                self.repositionGlassOverlay(in: pdfView)
                self.updatePageNumberOverlay(in: pdfView)
            }

            // Initial page number update
            DispatchQueue.main.async { [weak self, weak pdfView] in
                guard let self, let pdfView else { return }
                self.updatePageNumberOverlay(in: pdfView)
            }
        }

        func repositionGlassOverlay(in pdfView: PDFView) {
            guard let match = currentHighlightMatch,
                  let page = match.pages.first else {
                glassOverlay?.isHidden = true
                return
            }

            let pageBounds = match.bounds(for: page)
            let viewRect = pdfView.convert(pageBounds, from: page)
            let padded = viewRect.insetBy(dx: -3, dy: -1)

            // Hide if off-screen
            if !pdfView.bounds.intersects(padded) {
                glassOverlay?.isHidden = true
                return
            }

            if glassOverlay == nil {
                let view = NSView()
                view.wantsLayer = true
                view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
                view.layer?.cornerRadius = 3
                pdfView.addSubview(view)
                glassOverlay = view
            }

            glassOverlay?.frame = padded
            glassOverlay?.isHidden = false
        }

        // MARK: - Sticky Page Number Overlay

        func updatePageNumberOverlay(in pdfView: PDFView) {
            // Determine which page is visible at the top of the view
            let topCenter = CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.maxY - 20)
            guard let page = pdfView.page(for: topCenter, nearest: true),
                  let document = pdfView.document else {
                pageNumberOverlay?.isHidden = true
                return
            }

            let pageIndex = document.index(for: page)
            let totalPages = document.pageCount
            let isDark = NSApp.effectiveAppearance.name == .darkAqua
            let colorScheme: ColorScheme = isDark ? .dark : .light

            let pagePillView = Text("Page \(pageIndex + 1) of \(totalPages)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
                .environment(\.colorScheme, colorScheme)

            // Create or update the overlay
            if pageNumberOverlay == nil {
                let pillView = NSHostingView(rootView: AnyView(pagePillView))
                pillView.appearance = NSApp.effectiveAppearance
                pillView.translatesAutoresizingMaskIntoConstraints = false
                pdfView.addSubview(pillView)
                NSLayoutConstraint.activate([
                    pillView.topAnchor.constraint(equalTo: pdfView.topAnchor, constant: 12),
                    pillView.trailingAnchor.constraint(equalTo: pdfView.trailingAnchor, constant: -16),
                ])
                pageNumberOverlay = pillView
                currentVisiblePage = pageIndex
            } else if pageIndex != currentVisiblePage {
                currentVisiblePage = pageIndex
                pageNumberOverlay?.rootView = AnyView(pagePillView)
            }

            pageNumberOverlay?.isHidden = false
            pageNumberOverlay?.appearance = NSApp.effectiveAppearance

            // Keep it on top of other subviews
            if let overlay = pageNumberOverlay {
                pdfView.addSubview(overlay, positioned: .above, relativeTo: nil)
            }
        }

        // MARK: - PDFPageOverlayViewProvider

        func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> NSView? {
            return nil
        }

        // MARK: - Selection

        @objc func selectionChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let selection = pdfView.currentSelection,
                  let selectedText = selection.string,
                  !selectedText.isEmpty,
                  let document = pdfView.document else { return }

            guard let page = selection.pages.first else { return }
            lastPDFPage = page

            let pageIndex = document.index(for: page)

            let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            let firstWord = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
            guard !firstWord.isEmpty else { return }

            // Find all occurrences of this word on this page to determine which one was selected
            let allMatches = document.findString(firstWord, withOptions: .caseInsensitive)
            let pageMatches = allMatches.filter { match in
                match.pages.first.map { document.index(for: $0) } == pageIndex
            }

            var occurrence = 1
            if pageMatches.count > 1 {
                // Compare bounds to find which occurrence is closest to the selection
                let selBounds = selection.bounds(for: page)
                var bestDist = Double.infinity
                for (i, match) in pageMatches.enumerated() {
                    let matchBounds = match.bounds(for: page)
                    let dx = Double(matchBounds.midX - selBounds.midX)
                    let dy = Double(matchBounds.midY - selBounds.midY)
                    let dist = sqrt(dx * dx + dy * dy)
                    if dist < bestDist {
                        bestDist = dist
                        occurrence = i + 1
                    }
                }
            }

            onWordSelected(firstWord, pageIndex, occurrence)
        }
    }
}

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
}

/// A pronunciation mapping: find text and replace with spoken form.
struct PronunciationEntry: Identifiable, Codable {
    var id = UUID()
    var find: String
    var replace: String
}

/// A section header found in the processed text, with indentation level.
struct SectionItem: Identifiable {
    let id = UUID()
    let title: String
    let utf16Offset: Int
    let level: Int  // 0 = top-level (roman numeral / numeric), 1 = sub-section (letter / x.y)
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

/// Returns segments for before/after text with diff highlighting. Each tuple is (text, shouldBold).
private func diffSegments(before: String, after: String) -> (before: [(String, Bool)], after: [(String, Bool)]) {
    let b = Array(before)
    let a = Array(after)
    let n = b.count
    let m = a.count

    if n == 0 && m == 0 { return ([], []) }
    if n == 0 {
        return ([], [(after, true)])
    }
    if m == 0 {
        return ([(before, true)], [])
    }

    // LCS length table
    var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
    for i in 1...n {
        for j in 1...m {
            if b[i - 1] == a[j - 1] {
                dp[i][j] = dp[i - 1][j - 1] + 1
            } else {
                dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
            }
        }
    }

    // Backtrack: build beforeSegments and afterSegments (we traverse backwards so collect in reverse)
    var beforeSegments: [(String, Bool)] = []
    var afterSegments: [(String, Bool)] = []
    var i = n
    var j = m

    while i > 0 || j > 0 {
        if i > 0 && j > 0 && b[i - 1] == a[j - 1] {
            beforeSegments.append((String(b[i - 1]), false))
            afterSegments.append((String(a[j - 1]), false))
            i -= 1
            j -= 1
        } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
            afterSegments.append((String(a[j - 1]), true))
            j -= 1
        } else {
            beforeSegments.append((String(b[i - 1]), true))
            i -= 1
        }
    }

    // Reverse and merge adjacent segments with same bold state
    func merge(_ segs: [(String, Bool)]) -> [(String, Bool)] {
        let reversed = segs.reversed()
        var result: [(String, Bool)] = []
        for (s, bold) in reversed {
            if let last = result.last, last.1 == bold {
                result[result.count - 1] = (last.0 + s, bold)
            } else {
                result.append((s, bold))
            }
        }
        return result
    }

    return (merge(beforeSegments), merge(afterSegments))
}

/// Renders text from diff segments, bolding the highlighted parts.
private func diffRenderedText(segments: [(String, Bool)], fontSize: CGFloat) -> Text {
    segments.reduce(Text("")) { acc, seg in
        acc + (seg.1 ? Text(seg.0).fontWeight(.bold) : Text(seg.0))
    }
    .font(.system(size: fontSize))
}

/// Diff content is only computed when the disclosure is expanded, avoiding slow load.
private struct CleanupLogDiffContent: View {
    let entry: CleanupLogEntry

    var body: some View {
        let (beforeSegs, afterSegs) = diffSegments(before: entry.beforeText, after: entry.afterText)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                    Text("Before")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        diffRenderedText(segments: beforeSegs, fontSize: 11)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 180)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                    Text("After")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        diffRenderedText(segments: afterSegs, fontSize: 11)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 180)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 6)
    }
}

private struct CleanupLogEntryRow: View {
    let entry: CleanupLogEntry
    let onRevert: () -> Void

    var body: some View {
        DisclosureGroup {
            CleanupLogDiffContent(entry: entry)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.sectionTitle)
                        .font(.system(size: 12, weight: .medium))
                    Text("\(entry.charsRemoved) chars removed (\(entry.originalLength) → \(entry.cleanedLength))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Revert") {
                    onRevert()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
    }
}

struct ContentView: View {
    @StateObject private var speechManager = SpeechManager()
    @State private var rawText = ""
    @State private var cleanedText = ""
    @State private var displayText = ""
    @State private var aiCleanedChunks: [Int: String] = [:]
    @State private var displaySectionOffsets: [Int] = []
    @State private var pdfDocument: PDFDocument?
    @State private var pdfHighlightText = ""
    @State private var pdfHighlightPage: Int?
    @State private var pdfViewInstance: PDFView?
    @State private var sidebarMode: SidebarMode = .reader
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    @State private var searchQuery: String = ""
    @State private var lastSearchQuery: String = ""
    @State private var lastSearchResult: NSRange = NSRange(location: NSNotFound, length: 0)
    @State private var searchResults: [SearchResult] = []
    @State private var parsedSections: [SectionItem] = []
    @State private var showPronunciationEditor = false
    @State private var showOptionsEditor = false
    @AppStorage("ignoreReferences") private var ignoreReferences = true
    @AppStorage("ignoreBeforeAbstract") private var ignoreBeforeAbstract = true
    @AppStorage("skipCitations") private var skipCitations = true
    @AppStorage("replaceParentheses") private var replaceParentheses = true
    @AppStorage("speakGreekLetters") private var speakGreekLetters = true
    @AppStorage("speakMathSymbols") private var speakMathSymbols = true
    @AppStorage("removeFiguresAndTables") private var removeFiguresAndTables = false
    @AppStorage("aiCleanupPrompt") private var aiCleanupPrompt = """
        You are a text extraction assistant for a text to speech application. You receive text from a section of an academic paper. \
        Your job is to return ONLY the body prose text. Make the changes: \
        1. If there are errors or typos in the text fix them, \
        2. Remove figure captions (e.g. "Figure 1: ...", "Fig. 2. ..."), \
        3. Remove table content (rows of data, column headers), \
        4. Remove table captions (e.g. "Table 1: ..."), \
        5. Remove chart axis labels and legends, \
        6. Remove page headers and footers, \
        7. If there are garbage characters that are difficult for TTS to read remove them, \
        8. Remove sections that do not need to be read. Such as Concept lists, Keyword lists, or Reference Formats. \
        9. DO NOT remove page numbers, or modify white space, \
        10. Return the remaining text exactly as-is. Do not summarize or add any additional text.
        """
    @AppStorage("showEditor") private var showEditor = false
    @AppStorage("speedMultiplier") private var speedMultiplier = 2.0
    @State private var isCleaningInBackground = false
    @State private var backgroundCleanProgress: Double = 0
    @State private var backgroundCleanStatus = ""
    @State private var cleanupLog: [CleanupLogEntry] = []
    @State private var showCleanupLogSheet = false
    @State private var cleanupGeneration = 0
    @State private var showSummarySheet = false
    @State private var summaryText = ""
    @State private var isSummarizing = false
    @State private var summaryError = ""
    @State private var pronunciations: [PronunciationEntry] = Self.loadPronunciations()

    private static let defaultPronunciations: [PronunciationEntry] = [
        PronunciationEntry(find: "vCPU", replace: "virtual CPU"),
        PronunciationEntry(find: "e.g.", replace: "for example"),
        PronunciationEntry(find: "i.e.", replace: "that is"),
        PronunciationEntry(find: "et al.", replace: "and others"),
        PronunciationEntry(find: "Fig.", replace: "Figure"),
        PronunciationEntry(find: "#uctuating", replace: "fluctuating"),
        PronunciationEntry(find: "trade-o!", replace: "trade-off"),
        PronunciationEntry(find: " \"t ", replace: " fit "),
        PronunciationEntry(find: " \"rst ", replace: " first "),
        PronunciationEntry(find: " #oating ", replace: " floating "),
    ]

    private static func loadPronunciations() -> [PronunciationEntry] {
        guard let data = UserDefaults.standard.data(forKey: "pronunciations"),
              let decoded = try? JSONDecoder().decode([PronunciationEntry].self, from: data) else {
            return defaultPronunciations
        }
        return decoded
    }

    private static func savePronunciations(_ entries: [PronunciationEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: "pronunciations")
    }

    /// Search results sidebar view
    /// Pronunciation editor popover
    private var pronunciationEditorView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pronunciation Replacements")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

            HStack(spacing: 8) {
                Text("Find")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Speak As")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 28)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 2)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                ForEach($pronunciations) { $entry in
                    HStack(spacing: 8) {
                        TextField("Text", text: $entry.find)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                        TextField("Spoken as", text: $entry.replace)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                        Button(action: {
                            pronunciations.removeAll { $0.id == entry.id }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button(action: {
                    pronunciations.append(PronunciationEntry(find: "", replace: ""))
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Replacement")
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            HStack {
                Button("Close") {
                    Self.savePronunciations(pronunciations)
                    showPronunciationEditor = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply Now") {
                    Self.savePronunciations(pronunciations)
                    reprocessText()
                    showPronunciationEditor = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var cleanupLogSheetView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "sparkles")
                Text("AI Cleanup Log")
                    .font(.headline)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            if isCleaningInBackground {
                HStack(spacing: 8) {
                    ProgressView(value: backgroundCleanProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 120)
                        .padding(.horizontal, 12)
                    Text(backgroundCleanStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(action: stopCleanup) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Stop AI cleanup")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            Divider()

            if cleanupLog.isEmpty && !isCleaningInBackground {
                Text("No cleanup has run yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if cleanupLog.isEmpty {
                Text("Cleaning chunks...")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(cleanupLog) { entry in
                            CleanupLogEntryRow(entry: entry) {
                                aiCleanedChunks.removeValue(forKey: entry.chunkIndex)
                                cleanupLog = cleanupLog.filter { $0.id != entry.id }
                                buildDisplayText()
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: .infinity)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    showCleanupLogSheet = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var optionsEditorView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Options")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Content")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Toggle(isOn: $ignoreBeforeAbstract) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ignore Before Abstract")
                            .font(.system(size: 13))
                        Text("Remove text before the Abstract section")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $ignoreReferences) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ignore References")
                            .font(.system(size: 13))
                        Text("Truncate text after the References section")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $skipCitations) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Skip Citations")
                            .font(.system(size: 13))
                        Text("Remove inline citation brackets like [1], [2-5]")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("AI Cleanup")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Toggle(isOn: $removeFiguresAndTables) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable AI Cleanup")
                            .font(.system(size: 13))
                        Text("Use Apple Intelligence to clean text (strip figures, tables, fix typos, etc.)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Prompt")
                        .font(.system(size: 13))
                    Text("Instructions sent to the AI for each text chunk")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $aiCleanupPrompt)
                        .font(.system(size: 11))
                        .frame(minHeight: 120, maxHeight: 180)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Text Processing")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Toggle(isOn: $replaceParentheses) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replace Parentheses")
                            .font(.system(size: 13))
                        Text("Convert parentheses to commas for smoother speech")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $speakGreekLetters) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Speak Greek Letters")
                            .font(.system(size: 13))
                        Text("Read Greek symbols aloud (e.g. \u{03B1} as \"alpha\")")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $speakMathSymbols) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Speak Math Symbols")
                            .font(.system(size: 13))
                        Text("Read math symbols aloud (e.g. \u{2264} as \"less than or equal to\")")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("View")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Toggle(isOn: $showEditor) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Editor")
                            .font(.system(size: 13))
                        Text("Show the raw text editor tab in the sidebar")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    showOptionsEditor = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var summarySheetView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "apple.intelligence")
                    .font(.system(size: 16))
                Text("Section Summary")
                    .font(.headline)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            if !currentSectionName.isEmpty {
                Text(currentSectionName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }

            Divider()

            if isSummarizing {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Summarizing with Apple Intelligence...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if !summaryError.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                    Text(summaryError)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    Text(summaryText)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider()

            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(summaryText, forType: .string)
                }
                .disabled(summaryText.isEmpty || isSummarizing)
                Spacer()
                Button("Done") {
                    showSummarySheet = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    /// Get the text of the current section based on cursor position
    private func currentSectionText() -> String {
        let cursor = speechManager.cursorUTF16
        let nsText = displayText as NSString
        guard nsText.length > 0 else { return displayText }
        guard !displaySectionOffsets.isEmpty else { return displayText }

        let idx = (0..<parsedSections.count).last(where: { displaySectionOffsets[$0] <= cursor }) ?? 0
        let start = displaySectionOffsets[idx]
        let end = displaySectionOffsets[idx + 1]
        let range = NSRange(location: start, length: end - start)
        return nsText.substring(with: range)
    }

    /// Summarize the current section using Apple Intelligence
    private func summarizeCurrentSection() {
        let model = SystemLanguageModel.default

        switch model.availability {
        case .available:
            break
        case .unavailable(.deviceNotEligible):
            summaryError = "Apple Intelligence is not available on this device."
            summaryText = ""
            showSummarySheet = true
            return
        case .unavailable(.appleIntelligenceNotEnabled):
            summaryError = "Apple Intelligence is available but not enabled. Enable it in System Settings."
            summaryText = ""
            showSummarySheet = true
            return
        case .unavailable(.modelNotReady):
            summaryError = "The language model isn't ready yet. Please try again later."
            summaryText = ""
            showSummarySheet = true
            return
        case .unavailable:
            summaryError = "Apple Intelligence is unavailable."
            summaryText = ""
            showSummarySheet = true
            return
        }

        let sectionText = currentSectionText()
        guard !sectionText.isEmpty else { return }

        summaryText = ""
        summaryError = ""
        isSummarizing = true
        showSummarySheet = true

        Task {
            do {
                let instructions = """
                    You are a helpful research assistant. Provide a concise and comprehensive \
                    summary of the given text. Capture the main points and convey the author's \
                    intended meaning accurately. Do not add any information not in the original \
                    text. Keep the summary focused and appropriately brief.
                    """
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: sectionText)
                await MainActor.run {
                    summaryText = response.content
                    isSummarizing = false
                }
            } catch {
                await MainActor.run {
                    summaryError = "Summarization failed: \(error.localizedDescription)"
                    isSummarizing = false
                }
            }
        }
    }

    /// Build the current text processor options from state
    private var textProcessorOptions: TextProcessorOptions {
        TextProcessorOptions(
            skipCitations: skipCitations,
            replaceParentheses: replaceParentheses,
            speakGreekLetters: speakGreekLetters,
            speakMathSymbols: speakMathSymbols
        )
    }

    /// Reprocess the raw text with current pronunciation replacements
    private func reprocessText() {
        let wasPlaying = speechManager.isPlaying
        if wasPlaying {
            speechManager.stop()
        }
        cleanedText = applyPronunciations(TextProcessor.process(rawText, options: textProcessorOptions))
        aiCleanedChunks = [:]
        cleanupLog = []
        parseSections()
        buildDisplayText()
        if wasPlaying {
            speechManager.play(text: displayText)
        }
    }

    /// Apply pronunciation find-replace mappings to text
    private func applyPronunciations(_ text: String) -> String {
        var result = text

        // Strip text before Abstract if enabled
        if ignoreBeforeAbstract {
            if let abstractRange = findAbstractRange(in: result) {
                result = String(result[abstractRange.lowerBound...])
            }
        }

        // Truncate after References if enabled
        if ignoreReferences {
            let patterns = ["\n\nReferences\n\n", "\n\nREFERENCES\n\n", "\n\nReferences\n", "\n\nREFERENCES\n"]
            for pattern in patterns {
                if let range = result.range(of: pattern, options: .caseInsensitive) {
                    result = String(result[result.startIndex..<range.lowerBound])
                    break
                }
            }
        }

        for entry in pronunciations {
            guard !entry.find.isEmpty else { continue }
            result = result.replacingOccurrences(of: entry.find, with: entry.replace)
        }
        return result
    }

    /// Find the range where Abstract starts in the text.
    /// Supports: "Abstract\n", "Abstract—", "ABSTRACT\n", "ABSTRACT—", etc.
    private func findAbstractRange(in text: String) -> Range<String.Index>? {
        // Try regex: "Abstract" followed by optional whitespace then em-dash, en-dash, hyphen, colon, period, or newline
        // This handles both "Abstract\n..." (standalone) and "Abstract—Some text..." (inline)
        if let regex = try? NSRegularExpression(pattern: #"(?i)(?:^|\n\n?)abstract(?:\s*[—–\-:\.]\s*|\s*\n)"#, options: []) {
            let nsText = text as NSString
            if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) {
                let matchRange = match.range
                // Find the start of "Abstract" within the match (skip leading newlines)
                let matchStr = nsText.substring(with: matchRange)
                let abstractLocalRange = (matchStr as NSString).range(of: "abstract", options: .caseInsensitive)
                if abstractLocalRange.location != NSNotFound {
                    let abstractStart = matchRange.location + abstractLocalRange.location
                    return Range(NSRange(location: abstractStart, length: 0), in: text)
                }
            }
        }

        // Fallback: check if text starts with "abstract"
        let lower = text.lowercased()
        if lower.hasPrefix("abstract") {
            return text.startIndex..<text.startIndex
        }

        return nil
    }

    private var searchResultsView: some View {
        VStack(spacing: 0) {
            if searchResults.isEmpty {
                Spacer()
                Text(searchQuery.isEmpty ? "Use the search bar to find text" : "No results found")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                Spacer()
            } else {
                HStack {
                    Text("\(searchResults.count) result\(searchResults.count == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                List {
                    ForEach(searchResults) { result in
                        Button {
                            jumpToSearchResult(result)
                        } label: {
                            Text(highlightedSnippet(result.snippet, query: searchQuery))
                                .font(.system(size: 13))
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                    }
                    Color.clear.frame(height: 80)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Creates an AttributedString with the search query highlighted in bold
    private func highlightedSnippet(_ snippet: String, query: String) -> AttributedString {
        var attributed = AttributedString(snippet)
        let lowerSnippet = snippet.lowercased()
        let lowerQuery = query.lowercased()
        var searchStart = lowerSnippet.startIndex

        while let range = lowerSnippet.range(of: lowerQuery, range: searchStart..<lowerSnippet.endIndex) {
            let attrStart = AttributedString.Index(range.lowerBound, within: attributed)!
            let attrEnd = AttributedString.Index(range.upperBound, within: attributed)!
            attributed[attrStart..<attrEnd].font = .system(size: 13, weight: .bold)
            attributed[attrStart..<attrEnd].foregroundColor = .accentColor
            searchStart = range.upperBound
        }

        return attributed
    }

    /// Sections sidebar view — tree-style list of paper sections
    private var sectionsView: some View {
        VStack(spacing: 0) {
            if parsedSections.isEmpty {
                Spacer()
                Text("No sections found")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                Text("Import a PDF to see its structure")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))
                Spacer()
            } else {
                HStack {
                    Text("\(parsedSections.count) section\(parsedSections.count == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                List {
                    ForEach(parsedSections) { section in
                        Button {
                            jumpToSection(section)
                        } label: {
                            HStack(spacing: 6) {
                                if section.level > 0 {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                                Text(section.title)
                                    .font(.system(size: section.level == 0 ? 13 : 12,
                                                  weight: section.level == 0 ? .semibold : .regular))
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.leading, CGFloat(section.level) * 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                    }
                    Color.clear.frame(height: 80)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Parse section headers from cleaned text
    private func parseSections() {
        let text = cleanedText
        guard !text.isEmpty else {
            parsedSections = []
            return
        }

        var sections: [SectionItem] = []
        let nsText = text as NSString

        // Match section headers: standalone names, roman numeral, numeric, lettered
        let standaloneNames = [
            "Abstract", "Introduction", "Background", "Methods", "Methodology",
            "Results", "Discussion", "Conclusion", "Conclusions", "References",
            "Acknowledgments", "Acknowledgements", "Appendix", "Appendices",
            "Evaluation", "Overview", "Motivation", "Limitations", "Related Work",
        ]
        // Build case-insensitive standalone pattern
        let standaloneAlt = standaloneNames.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let patterns: [(pattern: String, level: Int)] = [
            // Standalone section headers (case-insensitive via (?i))
            (#"(?:^|\n\n)((?i)(?:"# + standaloneAlt + #")\S*[^\n]*)"#, 0),
            // Roman numeral sections: "I. TITLE", "II. TITLE"
            (#"(?:^|\n\n)([IVXLCDM]+\.\s+(?=[^\n]*[a-zA-Z])[^\n]+)"#, 0),
            // Top-level numeric: "1 Title" or "1. Title" (no dot in number)
            (#"(?:^|\n\n)(\d+\.?\s+(?=[^\n]*[a-zA-Z])[^\n]+)"#, 0),
            // Sub-section numeric: "1.1 Title", "2.3.1 Title"
            (#"(?:^|\n\n)(\d+\.\d+[\.\d]*\.?\s+(?=[^\n]*[a-zA-Z])[^\n]+)"#, 1),
            // Lettered sub-sections: "A. Title", "B. Title"
            (#"(?:^|\n\n)([A-Z]\.\s+(?=[^\n]*[a-zA-Z])[^\n]+)"#, 1),
        ]

        // Collect all matches with their positions
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
                // Skip very short or PAGE marker lines
                if title.count < 3 || title.hasPrefix("PAGE ") { continue }
                rawMatches.append(RawMatch(title: title, offset: titleRange.location, level: level))
            }
        }

        // Sort by position and deduplicate overlapping matches
        rawMatches.sort { $0.offset < $1.offset }

        var lastEnd = -1
        for raw in rawMatches {
            if raw.offset <= lastEnd { continue }  // skip overlapping
            sections.append(SectionItem(title: raw.title, utf16Offset: raw.offset, level: raw.level))
            lastEnd = raw.offset + (raw.title as NSString).length
        }

        parsedSections = sections
    }

    /// Jump to a section in the reader view
    /// Move cursor to Abstract if found in the text
    private func jumpToAbstract() {
        let nsText = displayText as NSString
        guard nsText.length > 0 else { return }

        if let idx = parsedSections.firstIndex(where: { $0.title.lowercased().hasPrefix("abstract") }) {
            speechManager.cursorUTF16 = displaySectionOffsets.indices.contains(idx) ? displaySectionOffsets[idx] : 0
            return
        }

        if let regex = try? NSRegularExpression(pattern: #"(?i)(?:^|\n\n?)abstract(?:\s*[—–\-:\.]\s*|\s*\n)"#, options: []) {
            if let match = regex.firstMatch(in: displayText, options: [], range: NSRange(location: 0, length: nsText.length)) {
                let matchStr = nsText.substring(with: match.range)
                let abstractLocalRange = (matchStr as NSString).range(of: "abstract", options: .caseInsensitive)
                if abstractLocalRange.location != NSNotFound {
                    speechManager.cursorUTF16 = match.range.location + abstractLocalRange.location
                    return
                }
            }
        }

        if displayText.lowercased().hasPrefix("abstract") {
            speechManager.cursorUTF16 = 0
        }
    }

    /// Jump to a specific section in the reader view
    private func jumpToSection(_ section: SectionItem) {
        if let coordinator = pdfViewInstance?.pageOverlayViewProvider as? PDFKitView.Coordinator {
            coordinator.bypassStabilization = true
        }

        speechManager.stop()
        if let idx = parsedSections.firstIndex(where: { $0.id == section.id }),
           displaySectionOffsets.indices.contains(idx) {
            speechManager.cursorUTF16 = displaySectionOffsets[idx]
        } else {
            speechManager.cursorUTF16 = section.utf16Offset
        }
        speechManager.cursorLengthUTF16 = (section.title as NSString).length

        sidebarMode = .reader
    }

    /// The name of the section the cursor is currently in
    private var currentSectionName: String {
        guard !parsedSections.isEmpty, !displaySectionOffsets.isEmpty else { return "" }
        let cursor = speechManager.cursorUTF16
        let idx = (0..<parsedSections.count).last(where: { displaySectionOffsets[$0] <= cursor }) ?? 0
        return parsedSections[idx].title
    }

    /// Detail view: PDF viewer + thumbnails with floating overlays
    private var detailView: some View {
        HStack(spacing: 0) {
            if pdfDocument != nil {
                ZStack {
                    PDFKitView(
                        document: pdfDocument,
                        highlightText: pdfHighlightText,
                        highlightPage: pdfHighlightPage,
                        onWordSelected: { word, _, _ in
                            searchQuery = word
                            performSearch()
                        },
                        onPDFViewReady: { view in
                            pdfViewInstance = view
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Bottom fade overlay on PDF view
                    VStack(spacing: 0) {
                        Spacer()
                        LinearGradient(
                            colors: [.clear, Color(nsColor: .windowBackgroundColor)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 100)
                    }
                    .allowsHitTesting(false)

                    // Floating playback pill at the bottom — centered over PDF area
                    VStack {
                        Spacer()
                        PlaybackPillView(
                            speechManager: speechManager,
                            displayText: displayText,
                            parsedSections: parsedSections,
                            displaySectionOffsets: displaySectionOffsets,
                            speedMultiplier: $speedMultiplier,
                            pdfViewInstance: pdfViewInstance,
                            jumpToSection: jumpToSection
                        )
                        .padding(.bottom, 20)
                    }
                }

                Divider()

                PDFThumbnailStrip(pdfView: pdfViewInstance)
                    .frame(width: 130)
                    .padding(.trailing, 4)
                    .frame(maxHeight: .infinity)
            } else {
                VStack {
                    Spacer()
                    Text("No PDF loaded")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                    Text("Click Import PDF to open a file")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 12))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
            }

        }
    }

    /// Sidebar content with floating liquid glass tab bar
    private var sidebarView: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch sidebarMode {
                case .reader:
                    ReaderTextView(
                        text: (displayText.isEmpty ? "" : displayText) + "\n\n\n\n\n",
                        cursorUTF16: speechManager.cursorUTF16,
                        cursorLengthUTF16: speechManager.cursorLengthUTF16,
                        onWordClicked: { utf16Offset in
                            jumpCursor(to: utf16Offset)
                        }
                    )
                case .editor:
                    TextEditor(text: $rawText)
                        .font(.system(size: 14))
                        .padding(4)
                        .contentMargins(.bottom, 60)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .search:
                    searchResultsView
                case .sections:
                    sectionsView
                case .hidden:
                    EmptyView()
                }
            }

            // Bottom fade overlay: transparent to solid background
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    colors: [.clear, Color(nsColor: .windowBackgroundColor)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
            }
            .allowsHitTesting(false)

            // Floating liquid glass tab bar with hit-testing blocker
            VStack {
                Spacer()
                HStack(spacing: 4) {
                    sidebarTabButton(icon: "person.wave.2.fill", mode: .reader)
                    if showEditor {
                        sidebarTabButton(icon: "square.and.pencil", mode: .editor)
                    }
                    sidebarTabButton(icon: "list.bullet.indent", mode: .sections)
                    sidebarTabButton(icon: "magnifyingglass", mode: .search)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            .background(
                VStack {
                    Spacer()
                    Color.clear
                        .frame(height: 50)
                        .contentShape(Rectangle())
                }
            )
            .allowsHitTesting(true)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 300, max: 500)
    }

    private var mainContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarView
        } detail: {
            detailView
        }
        .toolbar(id: "mainToolbarTest4") {
            
            // Group 1: Load PDF
            ToolbarItem(id: "load", placement: .automatic) {
                Button(action: importPDF) {
                    Label("Load", systemImage: "doc.fill")
                }
                .help("Load PDF")
            }
            
            // Group 4: Pronunciation
            ToolbarItem(id: "pronunciation", placement: .automatic) {
                Button(action: { showPronunciationEditor = true }) {
                    Label("Pronounce", systemImage: "text.word.spacing")
                }
                .help("Edit pronunciation replacements")
            }
            
            // Group 5: Settings
            ToolbarItem(id: "settings", placement: .automatic) {
                Button(action: { showOptionsEditor = true }) {
                    Label("Options", systemImage: "gearshape")
                }
                .help("Reader options")
            }

            // Group 2: AI tools
            ToolbarItem(id: "ai", placement: .automatic) {
                HStack(spacing: 6) {
                    Button(action: { summarizeCurrentSection() }) {
                        Label("AI Summary", systemImage: "apple.intelligence")
                    }
                    .help("Summarize current section with Apple Intelligence")
                    .disabled(displayText.isEmpty)

                    if isCleaningInBackground {
                        Button(action: stopCleanup) {
                            Label("Stop Cleanup", systemImage: "stop.fill")
                        }
                        .help("Stop AI cleanup")
                    } else {
                        Button(action: { startChunkBasedAICleanup() }) {
                            Label("AI Cleanup", systemImage: "sparkles")
                        }
                        .disabled(!removeFiguresAndTables || cleanedText.isEmpty)
                        .help(removeFiguresAndTables ? "Run AI cleanup on the text" : "Enable AI Cleanup in Options first")
                    }

                    ProgressView(value: backgroundCleanProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 60)
                        .opacity(isCleaningInBackground ? 1.0 : 0.3)

                    Button(action: { showCleanupLogSheet = true }) {
                        Label("AI Log", systemImage: "list.bullet.rectangle")
                            .overlay(alignment: .topTrailing) {
                                if !cleanupLog.isEmpty {
                                    Text("\(cleanupLog.count)")
                                        .font(.system(size: 9))
                                        .padding(2)
                                        .background(Capsule().fill(Color.accentColor))
                                        .foregroundStyle(.white)
                                        .offset(x: 6, y: -6)
                                }
                            }
                    }
                    .help(cleanupLog.isEmpty ? "View AI cleanup log (no entries yet)" : "View AI cleanup log (\(cleanupLog.count) entries)")
                }
            }

            ToolbarSpacer(.flexible, placement: .automatic)
            
            // Group 3: PDF Zoom controls
            ToolbarItem(id: "zoom", placement: .automatic) {
                HStack(spacing: 2) {
                    Button(action: { pdfViewInstance?.zoomOut(nil) }) {
                        Label("Zoom Out", systemImage: "minus.magnifyingglass")
                    }
                    .help("Zoom out PDF")
                    .disabled(pdfViewInstance == nil || !(pdfViewInstance?.canZoomOut ?? false))

                    Button(action: {
                        pdfViewInstance?.autoScales = true
                    }) {
                        Label("Actual Size", systemImage: "1.magnifyingglass")
                    }
                    .help("Reset PDF zoom to fit")
                    .disabled(pdfViewInstance == nil)

                    Button(action: { pdfViewInstance?.zoomIn(nil) }) {
                        Label("Zoom In", systemImage: "plus.magnifyingglass")
                    }
                    .help("Zoom in PDF")
                    .disabled(pdfViewInstance == nil || !(pdfViewInstance?.canZoomIn ?? false))
                }
            }
            
            ToolbarSpacer(.fixed, placement: .automatic)
            
            // Group 6: Search
            ToolbarItem(id: "search", placement: .automatic) {
                ToolbarSearchField(text: $searchQuery, prompt: "Search") {
                    performSearch()
                }
                .frame(width: 200)
            }
        }
        //.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .sheet(isPresented: $showPronunciationEditor) {
            pronunciationEditorView
                .frame(width: 450)
        }
        .sheet(isPresented: $showOptionsEditor) {
            optionsEditorView
                .frame(width: 420)
        }
        .sheet(isPresented: $showSummarySheet) {
            summarySheetView
                .frame(width: 500, height: 400)
        }
        .sheet(isPresented: $showCleanupLogSheet) {
            cleanupLogSheetView
                .frame(minWidth: 720, minHeight: 400)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCleanupLog)) { _ in
            showCleanupLogSheet = true
        }
        .frame(minWidth: 900, minHeight: 500)
    }

    var body: some View {
        mainContent
            .onChange(of: searchQuery, handleSearchQueryChange)
            .onChange(of: ignoreReferences) { _, _ in reprocessText() }
            .onChange(of: ignoreBeforeAbstract) { _, _ in reprocessText() }
            .onChange(of: skipCitations) { _, _ in reprocessText() }
            .onChange(of: removeFiguresAndTables, handleAICleanupToggle)
            .onChange(of: replaceParentheses) { _, _ in reprocessText() }
            .onChange(of: speakGreekLetters) { _, _ in reprocessText() }
            .onChange(of: speakMathSymbols) { _, _ in reprocessText() }
            .onChange(of: showEditor, handleShowEditorChange)
            .onChange(of: rawText, handleRawTextChange)
            .onChange(of: speechManager.cursorUTF16) { _, _ in updatePDFHighlight() }
            .onAppear(perform: handleOnAppear)
            .onDisappear { speechManager.stop() }
    }

    private func handleSearchQueryChange(_: String, newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            lastSearchQuery = ""
            lastSearchResult = NSRange(location: NSNotFound, length: 0)
            speechManager.cursorLengthUTF16 = 0
        } else if trimmed != lastSearchQuery {
            lastSearchResult = NSRange(location: NSNotFound, length: 0)
        }
    }

    private func handleAICleanupToggle(_: Bool, enabled: Bool) {
        if !enabled {
            aiCleanedChunks = [:]
            cleanupLog = []
            buildDisplayText()
        }
    }

    private func handleShowEditorChange(_: Bool, newValue: Bool) {
        if !newValue && sidebarMode == .editor {
            sidebarMode = .reader
        }
    }

    private func handleRawTextChange(_: String, newValue: String) {
        let wasPlaying = speechManager.isPlaying
        if wasPlaying { speechManager.stop() }
        cleanedText = applyPronunciations(TextProcessor.process(newValue, options: textProcessorOptions))
        aiCleanedChunks = [:]
        cleanupLog = []
        speechManager.resetCursor()
        parseSections()
        buildDisplayText()
        jumpToAbstract()
    }

    private func handleOnAppear() {
        if pdfDocument == nil {
            importPDF()
        }
    }

    // MARK: - Sidebar Management

    /// A single tab button for the sidebar pill. Selected tab gets its own glass highlight.
    private func sidebarTabButton(icon: String, mode: SidebarMode) -> some View {
        let isSelected = sidebarMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                sidebarMode = mode
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            Group {
                if isSelected {
                    Capsule()
                        .fill(.white.opacity(0.2))
                }
            }
        )
        .opacity(isSelected ? 1.0 : 0.45)
    }
    
    // MARK: - Page Mapping

    // MARK: - Search

    private func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        guard !displayText.isEmpty else { return }

        // Bypass stabilization so the PDF highlight jumps immediately
        if let coordinator = pdfViewInstance?.pageOverlayViewProvider as? PDFKitView.Coordinator {
            coordinator.bypassStabilization = true
        }

        let nsText = displayText as NSString
        let textLength = nsText.length
        guard textLength > 0 else { return }

        // Find ALL matches and populate search results
        var results: [SearchResult] = []
        var searchRange = NSRange(location: 0, length: textLength)
        let contextChars = 40

        while searchRange.location < textLength {
            let found = nsText.range(of: query, options: [.caseInsensitive], range: searchRange)
            guard found.location != NSNotFound else { break }

            // Build snippet with surrounding context
            let snippetStart = max(0, found.location - contextChars)
            let snippetEnd = min(textLength, found.location + found.length + contextChars)
            var snippet = nsText.substring(with: NSRange(location: snippetStart, length: snippetEnd - snippetStart))
            snippet = snippet.replacingOccurrences(of: "\n", with: " ")
            if snippetStart > 0 { snippet = "…" + snippet }
            if snippetEnd < textLength { snippet = snippet + "…" }

            results.append(SearchResult(range: found, snippet: snippet))

            searchRange.location = found.location + max(found.length, 1)
            searchRange.length = textLength - searchRange.location
        }

        searchResults = results
        sidebarMode = .search
        columnVisibility = .all

        lastSearchQuery = query
    }

    /// Jump to a specific search result: switch to reader and select the text
    private func jumpToSearchResult(_ result: SearchResult) {
        // Bypass stabilization so the PDF highlight jumps immediately
        if let coordinator = pdfViewInstance?.pageOverlayViewProvider as? PDFKitView.Coordinator {
            coordinator.bypassStabilization = true
        }

        speechManager.stop()
        speechManager.cursorUTF16 = result.range.location
        speechManager.cursorLengthUTF16 = result.range.length

        lastSearchResult = result.range

        sidebarMode = .reader
    }

    /// Parses PAGE markers in the cleaned text to find section boundaries.
    /// Returns [(pageNumber, sectionStartUTF16, sectionEndUTF16)].
    private func pageRangesInCleanedText() -> [(page: Int, start: Int, end: Int)] {
        let nsText = displayText as NSString
        let pattern = "PAGE (\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: displayText, range: NSRange(location: 0, length: nsText.length))

        var ranges: [(page: Int, start: Int, end: Int)] = []
        for (i, match) in matches.enumerated() {
            let pageNumRange = match.range(at: 1)
            let pageNum = Int(nsText.substring(with: pageNumRange)) ?? 0
            let sectionStart = match.range.location + match.range.length
            let sectionEnd = (i + 1 < matches.count) ? matches[i + 1].range.location : nsText.length
            ranges.append((page: pageNum, start: sectionStart, end: sectionEnd))
        }
        return ranges
    }

    /// Determines which PDF page the given UTF-16 offset falls in.
    private func pageForOffset(_ offset: Int) -> Int? {
        let pages = pageRangesInCleanedText()
        return pages.last(where: { $0.start <= offset })?.page
    }

    // MARK: - Reader → PDF Highlighting

    private func updatePDFHighlight() {
        guard pdfDocument != nil, !displayText.isEmpty else { return }

        let nsText = displayText as NSString
        let cursor = min(speechManager.cursorUTF16, nsText.length)

        // Determine which page the cursor is on from PAGE markers
        pdfHighlightPage = pageForOffset(cursor)

        // Get a context window of ~40 chars from cursor
        let contextStart = max(0, cursor)
        let contextEnd = min(nsText.length, cursor + 40)
        let contextLength = contextEnd - contextStart

        guard contextLength > 0 else { return }

        var phrase = nsText.substring(with: NSRange(location: contextStart, length: contextLength))
        // Trim to whole words
        if let lastSpace = phrase.lastIndex(of: " ") {
            phrase = String(phrase[phrase.startIndex..<lastSpace])
        }
        // Take first few words for a focused search
        let words = phrase.split(separator: " ")
        // Filter out PAGE markers from the search phrase
        let filteredWords = words.filter { !$0.hasPrefix("PAGE") }
        let searchPhrase = filteredWords.prefix(4).joined(separator: " ")

        if !searchPhrase.isEmpty {
            pdfHighlightText = searchPhrase
        }
    }

    // MARK: - Cursor Jumping

    private func jumpCursor(to utf16Offset: Int) {
        // Bypass stabilization so the PDF highlight jumps immediately
        if let coordinator = pdfViewInstance?.pageOverlayViewProvider as? PDFKitView.Coordinator {
            coordinator.bypassStabilization = true
        }

        speechManager.stop()
        speechManager.cursorUTF16 = utf16Offset
        speechManager.cursorLengthUTF16 = 0
    }

    // MARK: - PDF → Reader (word selection)

    /// Jumps the reader cursor to the word selected in the PDF.
    /// Uses page number and occurrence counting for precise matching.
    private func jumpToWord(_ word: String, fromPage pageIndex: Int, occurrence: Int) {
        guard !displayText.isEmpty, !word.isEmpty else { return }

        // Bypass stabilization so the PDF highlight jumps immediately
        if let coordinator = pdfViewInstance?.pageOverlayViewProvider as? PDFKitView.Coordinator {
            coordinator.bypassStabilization = true
        }

        let cleanedWord = TextProcessor.process(word, options: textProcessorOptions)
        guard !cleanedWord.isEmpty else { return }

        let nsText = displayText as NSString
        let pages = pageRangesInCleanedText()

        // Try to find the nth occurrence within the matching page section
        if let section = pages.first(where: { $0.page == pageIndex }) {
            let sectionEnd = section.end

            var found = 0
            var searchStart = section.start
            while searchStart < sectionEnd {
                let remaining = NSRange(location: searchStart, length: sectionEnd - searchStart)
                let range = nsText.range(of: cleanedWord, options: .caseInsensitive, range: remaining)
                if range.location == NSNotFound { break }
                found += 1
                if found == occurrence {
                    jumpCursor(to: range.location)
                    return
                }
                searchStart = range.location + range.length
            }

            // Fallback: first occurrence in this page section
            let sectionRange = NSRange(location: section.start, length: sectionEnd - section.start)
            let range = nsText.range(of: cleanedWord, options: .caseInsensitive, range: sectionRange)
            if range.location != NSNotFound {
                jumpCursor(to: range.location)
                return
            }
        }

        // Final fallback: search from current position (for non-PDF text)
        let currentOffset = speechManager.cursorUTF16
        let searchStart = min(currentOffset, nsText.length)
        let forwardRange = NSRange(location: searchStart, length: nsText.length - searchStart)
        var foundRange = nsText.range(of: cleanedWord, options: .caseInsensitive, range: forwardRange)

        if foundRange.location == NSNotFound {
            foundRange = nsText.range(of: cleanedWord, options: .caseInsensitive, range: NSRange(location: 0, length: nsText.length))
        }

        if foundRange.location != NSNotFound {
            jumpCursor(to: foundRange.location)
        }
    }

    // MARK: - PDF Import

    private func importPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.message = "Select a PDF to import"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let document = PDFDocument(url: url) else { return }

        pdfDocument = document
        cleanupGeneration += 1

        var pageTexts: [Int: String] = [:]
        for i in 0..<document.pageCount {
            pageTexts[i] = document.page(at: i)?.string ?? ""
        }
        rawText = assembleExtractedText(document: document, pageTexts: pageTexts)
    }

    /// True if the only differences between original and modified are whitespace (spaces, newlines, etc).
    private func isWhitespaceOnlyChange(original: String, modified: String) -> Bool {
        let norm = { (s: String) in s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ") }
        return norm(original) == norm(modified)
    }

    /// Splits text into ~1000-character chunks, breaking at word boundaries when possible.
    private func makeChunks(from text: String, chunkSize: Int = 1000) -> [(start: Int, end: Int)] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }
        var chunks: [(Int, Int)] = []
        var pos = 0
        while pos < nsText.length {
            var end = min(pos + chunkSize, nsText.length)
            if end < nsText.length {
                let fragment = nsText.substring(with: NSRange(location: pos, length: end - pos))
                if let nl = fragment.lastIndex(of: "\n") {
                    end = pos + fragment.distance(from: fragment.startIndex, to: nl) + 1
                } else if let sp = fragment.lastIndex(of: " ") {
                    end = pos + fragment.distance(from: fragment.startIndex, to: sp) + 1
                }
            }
            chunks.append((pos, end))
            pos = end
        }
        return chunks
    }

    /// Builds displayText from cleanedText, applying AI-cleaned chunk overrides.
    /// Also updates displaySectionOffsets for mapping between displayText and sections.
    private func buildDisplayText() {
        let text = cleanedText
        let nsText = text as NSString
        guard nsText.length > 0 else {
            displayText = ""
            displaySectionOffsets = []
            return
        }

        if aiCleanedChunks.isEmpty {
            displayText = text
            displaySectionOffsets = parsedSections.isEmpty ? [0, nsText.length] : parsedSections.map { $0.utf16Offset } + [nsText.length]
            return
        }

        let chunks = makeChunks(from: text)
        var result = ""
        for (idx, (start, end)) in chunks.enumerated() {
            let original = nsText.substring(with: NSRange(location: start, length: end - start))
            result += aiCleanedChunks[idx] ?? original
        }

        // Compute displaySectionOffsets: offsets[i] = displayText position where section i starts
        var offsets: [Int]
        if parsedSections.isEmpty {
            offsets = [0, (result as NSString).length]
        } else {
            var outPos = 0
            var sectionIdx = 0
            offsets = [0]
            for (idx, (start, end)) in chunks.enumerated() {
                let content = aiCleanedChunks[idx] ?? nsText.substring(with: NSRange(location: start, length: end - start))
                let len = (content as NSString).length
                while sectionIdx < parsedSections.count {
                    let s = parsedSections[sectionIdx].utf16Offset
                    if start <= s && s < end {
                        offsets.append(outPos)
                        sectionIdx += 1
                    } else {
                        break
                    }
                }
                outPos += len
            }
            while offsets.count < parsedSections.count + 1 {
                offsets.append(outPos)
            }
        }

        displayText = result
        displaySectionOffsets = offsets

        let newLen = (result as NSString).length
        if speechManager.cursorUTF16 >= newLen {
            speechManager.cursorUTF16 = max(0, newLen - 1)
        }
    }

    /// Kicks off background AI cleanup of 500-char chunks (from cleanedText) containing figure/table indicators.
    /// Updates displayText incrementally as each chunk is cleaned. Changelog entries are labeled by section name.
    private func stopCleanup() {
        cleanupGeneration += 1
    }

    private func startChunkBasedAICleanup() {
        guard removeFiguresAndTables else { return }

        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return }

        let currentGeneration = cleanupGeneration
        let text = cleanedText
        let nsText = text as NSString

        guard nsText.length > 0 else { return }

        let chunks = makeChunks(from: text)
        let indicesToClean = chunks.enumerated()
            .filter { (_, range) in range.end - range.start >= 200 }
            .map(\.offset)

        guard !indicesToClean.isEmpty else { return }

        isCleaningInBackground = true
        backgroundCleanProgress = 0
        backgroundCleanStatus = "Cleaning 1/\(indicesToClean.count)..."

        // Precompute section names for changelog labels (which section each chunk falls in)
        let sectionTitlesByChunk: [Int: String] = Dictionary(uniqueKeysWithValues: indicesToClean.map { idx in
            let start = chunks[idx].start
            let title: String
            if parsedSections.isEmpty {
                title = "Chunk \(idx + 1)"
            } else {
                let i = (0..<parsedSections.count).last(where: { parsedSections[$0].utf16Offset <= start }) ?? 0
                title = parsedSections[i].title
            }
            return (idx, title)
        })

        Task {
            for (step, chunkIdx) in indicesToClean.enumerated() {
                if cleanupGeneration != currentGeneration {
                    await MainActor.run { isCleaningInBackground = false }
                    return
                }

                await MainActor.run {
                    backgroundCleanProgress = Double(step) / Double(indicesToClean.count)
                    backgroundCleanStatus = "Cleaning \(step + 1)/\(indicesToClean.count)..."
                }

                let (start, end) = chunks[chunkIdx]
                let chunkText = nsText.substring(with: NSRange(location: start, length: end - start))
                let sectionTitle = sectionTitlesByChunk[chunkIdx] ?? "Chunk \(chunkIdx + 1)"
                let originalLength = chunkText.count

                let cleanedChunk = await aiCleanSection(chunkText)
                let hasMeaningfulChange = !isWhitespaceOnlyChange(original: chunkText, modified: cleanedChunk)
                let finalChunk = hasMeaningfulChange ? cleanedChunk : chunkText

                await MainActor.run {
                    if cleanupGeneration != currentGeneration { return }
                    if hasMeaningfulChange {
                        aiCleanedChunks[chunkIdx] = finalChunk
                        cleanupLog.append(CleanupLogEntry(
                            chunkIndex: chunkIdx,
                            sectionTitle: sectionTitle,
                            beforeText: chunkText,
                            afterText: finalChunk,
                            originalLength: originalLength,
                            cleanedLength: finalChunk.count
                        ))
                        buildDisplayText()
                    }
                }
            }

            await MainActor.run {
                backgroundCleanProgress = 1.0
                backgroundCleanStatus = ""
                isCleaningInBackground = false
            }
        }
    }

    /// Uses Apple Intelligence to clean text according to the user-configurable prompt.
    private func aiCleanSection(_ text: String) async -> String {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return text }
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return text }

        do {
            let instructions = aiCleanupPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let session = LanguageModelSession(instructions: instructions.isEmpty ? "Return the text unchanged." : instructions)
            let response = try await session.respond(to: text)
            return response.content
        } catch {
            return text
        }
    }

    /// Assembles the final extracted text with PAGE markers from per-page text.
    private func assembleExtractedText(document: PDFDocument, pageTexts: [Int: String]) -> String {
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

#Preview {
    ContentView()
}
