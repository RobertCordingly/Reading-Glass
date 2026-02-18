import PDFKit
import AppKit
import SwiftUI
import FoundationModels

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
        parsedSections = SectionParser.parse(text: cleanedText)
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
                    EditorView(text: $rawText)
                case .search:
                    SearchResultsView(searchQuery: searchQuery, searchResults: searchResults, onResultSelected: jumpToSearchResult)
                case .sections:
                    SectionsView(sections: parsedSections, onSectionSelected: jumpToSection)
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
            
            ToolbarItem(id: "load", placement: .automatic) {
                Button(action: importPDF) {
                    Label("Load", systemImage: "doc.fill")
                }
                .help("Load PDF")
            }
            
            ToolbarItem(id: "pronunciation", placement: .automatic) {
                Button(action: { showPronunciationEditor = true }) {
                    Label("Pronounce", systemImage: "text.word.spacing")
                }
                .help("Edit pronunciation replacements")
            }
            
            ToolbarItem(id: "settings", placement: .automatic) {
                Button(action: { showOptionsEditor = true }) {
                    Label("Options", systemImage: "gearshape")
                }
                .help("Reader options")
            }
            
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
            
            ToolbarItem(id: "zoom", placement: .automatic) {
                HStack(spacing: 2) {
                    Button(action: { pdfViewInstance?.zoomOut(nil) }) {
                        Label("Zoom Out", systemImage: "minus.magnifyingglass")
                    }
                    .help("Zoom out PDF")
                    .disabled(pdfViewInstance == nil || !(pdfViewInstance?.canZoomOut ?? false))
                    Button(action: { pdfViewInstance?.autoScales = true }) {
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
            
            ToolbarItem(id: "search", placement: .automatic) {
                ToolbarSearchField(text: $searchQuery, prompt: "Search") {
                    performSearch()
                }
                .frame(width: 200)
            }
        }
        .sheet(isPresented: $showPronunciationEditor) {
            PronunciationEditorView(
                pronunciations: $pronunciations,
                onClose: {
                    Self.savePronunciations(pronunciations)
                    showPronunciationEditor = false
                },
                onApply: {
                    Self.savePronunciations(pronunciations)
                    reprocessText()
                    showPronunciationEditor = false
                }
            )
            .frame(width: 450)
        }
        .sheet(isPresented: $showOptionsEditor) {
            OptionsView(
                ignoreBeforeAbstract: $ignoreBeforeAbstract,
                ignoreReferences: $ignoreReferences,
                skipCitations: $skipCitations,
                removeFiguresAndTables: $removeFiguresAndTables,
                aiCleanupPrompt: $aiCleanupPrompt,
                replaceParentheses: $replaceParentheses,
                speakGreekLetters: $speakGreekLetters,
                speakMathSymbols: $speakMathSymbols,
                showEditor: $showEditor,
                onDone: { showOptionsEditor = false }
            )
            .frame(width: 420)
        }
        .sheet(isPresented: $showSummarySheet) {
            SummarySheetView(
                sectionName: currentSectionName,
                summaryText: summaryText,
                isSummarizing: isSummarizing,
                summaryError: summaryError,
                onDone: { showSummarySheet = false }
            )
            .frame(width: 500, height: 400)
        }
        .sheet(isPresented: $showCleanupLogSheet) {
            CleanupLogView(
                cleanupLog: cleanupLog,
                isCleaningInBackground: isCleaningInBackground,
                backgroundCleanProgress: backgroundCleanProgress,
                backgroundCleanStatus: backgroundCleanStatus,
                onStopCleanup: stopCleanup,
                onRevert: { entry in
                    aiCleanedChunks.removeValue(forKey: entry.chunkIndex)
                    cleanupLog = cleanupLog.filter { $0.id != entry.id }
                    buildDisplayText()
                },
                onDone: { showCleanupLogSheet = false }
            )
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
        parsedSections = SectionParser.parse(text: cleanedText)
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
