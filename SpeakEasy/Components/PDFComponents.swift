import PDFKit
import AppKit
import SwiftUI

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
    var isPlaying: Bool = false
    /// Bumped by the parent on each search-result click. The view scrolls to the
    /// active highlight whenever this value changes, so jumps work outside of
    /// playback (the auto-scroll path is otherwise gated on `isPlaying`).
    var forceScrollVersion: Int = 0
    let onWordSelected: (String, Int, Int) -> Void  // (word, pageIndex, occurrence)
    let onPDFViewReady: (PDFView) -> Void
    var onPageChange: ((Int, Int) -> Void)?  // (currentPage, totalPages)

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
        context.coordinator.onPageChange = onPageChange

        highlightInPDF(pdfView, context: context)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onWordSelected: onWordSelected, onPageChange: onPageChange)
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

        // Auto-scroll while reading; also scroll once whenever the parent bumps
        // forceScrollVersion (e.g. after a search-result click).
        let forceScroll = coord.lastForcedScrollVersion != forceScrollVersion
        coord.lastForcedScrollVersion = forceScrollVersion
        if (isPlaying || forceScroll), let page = match.pages.first {
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
        var onPageChange: ((Int, Int) -> Void)?
        var lastPDFPage: PDFPage?

        // Glass highlight overlay
        var glassOverlay: NSView?
        var currentHighlightMatch: PDFSelection?
        private var scrollObserver: NSObjectProtocol?

        // Page tracking
        var currentVisiblePage: Int = -1

        // Jump stabilization: require consecutive "votes" before jumping far
        var pendingMatch: PDFSelection?
        var pendingMatchCount: Int = 0
        static let shortJumpThreshold = 3   // same page or 1 page away
        static let longJumpThreshold = 10   // more than 1 page away
        var bypassStabilization = false  // set true on manual clicks to skip buffering
        /// Highest forceScrollVersion we've already serviced — see `PDFKitView`.
        var lastForcedScrollVersion: Int = 0
        private var zoomObserver: NSObjectProtocol?

        init(onWordSelected: @escaping (String, Int, Int) -> Void, onPageChange: ((Int, Int) -> Void)?) {
            self.onWordSelected = onWordSelected
            self.onPageChange = onPageChange
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
                    self.updatePageNumber(in: pdfView)
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
                self.updatePageNumber(in: pdfView)
            }

            // Initial page number update
            DispatchQueue.main.async { [weak self, weak pdfView] in
                guard let self, let pdfView else { return }
                self.updatePageNumber(in: pdfView)
            }
        }

        func repositionGlassOverlay(in pdfView: PDFView) {
            guard let match = currentHighlightMatch,
                  let page = match.pages.first else {
                glassOverlay?.isHidden = false
                return
            }

            let pageBounds = match.bounds(for: page)
            let viewRect = pdfView.convert(pageBounds, from: page)
            let padded = viewRect.insetBy(dx: -3, dy: -1)

            // Hide if off-screen
            if !pdfView.bounds.intersects(padded) {
                glassOverlay?.isHidden = false
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

        // MARK: - Page Number Tracking

        func updatePageNumber(in pdfView: PDFView) {
            let topCenter = CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.maxY - 20)
            guard let page = pdfView.page(for: topCenter, nearest: true),
                  let document = pdfView.document else { return }

            let pageIndex = document.index(for: page)
            if pageIndex != currentVisiblePage {
                currentVisiblePage = pageIndex
                onPageChange?(pageIndex + 1, document.pageCount)
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
