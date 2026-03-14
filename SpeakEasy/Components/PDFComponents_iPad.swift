#if os(iOS)
import PDFKit
import SwiftUI
import UIKit

// MARK: - PDFThumbnailStrip

/// Wraps PDFKit's PDFThumbnailView for iPadOS.
struct PDFThumbnailStrip: UIViewRepresentable {
    let pdfView: PDFView?

    func makeUIView(context: Context) -> PDFThumbnailView {
        let thumbnailView = PDFThumbnailView()
        thumbnailView.thumbnailSize = CGSize(width: 120, height: 165)
        thumbnailView.pdfView = pdfView
        return thumbnailView
    }

    func updateUIView(_ thumbnailView: PDFThumbnailView, context: Context) {
        if thumbnailView.pdfView !== pdfView {
            thumbnailView.pdfView = pdfView
        }
    }
}

// MARK: - ToolbarSearchField

/// Pure SwiftUI search field for the iPadOS toolbar.
struct ToolbarSearchField: View {
    @Binding var text: String
    let prompt: String
    let onSubmit: () -> Void

    var body: some View {
        TextField(prompt, text: $text)
            .textFieldStyle(.roundedBorder)
            .submitLabel(.search)
            .onSubmit(onSubmit)
    }
}

// MARK: - PDFKitView

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument?
    let highlightText: String
    let highlightPage: Int?
    var isPlaying: Bool = false
    let onWordSelected: (String, Int, Int) -> Void
    let onPDFViewReady: (PDFView) -> Void
    var onPageChange: ((Int, Int) -> Void)?

    func makeUIView(context: Context) -> PDFView {
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

    func updateUIView(_ pdfView: PDFView, context: Context) {
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

        if isPlaying, let page = match.pages.first {
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

        coord.setupScrollTracking(for: pdfView)
        coord.repositionGlassOverlay(in: pdfView)
    }

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

    // MARK: - Coordinator

    class Coordinator: NSObject, PDFPageOverlayViewProvider {
        var onWordSelected: (String, Int, Int) -> Void
        var onPageChange: ((Int, Int) -> Void)?
        var lastPDFPage: PDFPage?

        var glassOverlay: UIView?
        var currentHighlightMatch: PDFSelection?
        private var scrollOffsetObserver: NSKeyValueObservation?
        private var zoomObserver: NSObjectProtocol?

        var currentVisiblePage: Int = -1
        var pendingMatch: PDFSelection?
        var pendingMatchCount: Int = 0
        static let shortJumpThreshold = 3
        static let longJumpThreshold = 10
        var bypassStabilization = false

        init(onWordSelected: @escaping (String, Int, Int) -> Void, onPageChange: ((Int, Int) -> Void)?) {
            self.onWordSelected = onWordSelected
            self.onPageChange = onPageChange
        }

        deinit {
            scrollOffsetObserver?.invalidate()
            if let obs = zoomObserver { NotificationCenter.default.removeObserver(obs) }
        }

        // MARK: - Scroll tracking

        func setupScrollTracking(for pdfView: PDFView) {
            guard scrollOffsetObserver == nil else { return }

            // Find the internal UIScrollView inside PDFView
            func findScrollView(_ view: UIView) -> UIScrollView? {
                if let sv = view as? UIScrollView { return sv }
                for sub in view.subviews {
                    if let sv = findScrollView(sub) { return sv }
                }
                return nil
            }

            if let scrollView = findScrollView(pdfView) {
                scrollOffsetObserver = scrollView.observe(\.contentOffset, options: [.new]) { [weak self, weak pdfView] _, _ in
                    DispatchQueue.main.async {
                        guard let self, let pdfView else { return }
                        self.repositionGlassOverlay(in: pdfView)
                        self.updatePageNumber(in: pdfView)
                    }
                }
            }

            zoomObserver = NotificationCenter.default.addObserver(
                forName: .PDFViewScaleChanged,
                object: pdfView,
                queue: .main
            ) { [weak self, weak pdfView] _ in
                guard let self, let pdfView else { return }
                self.repositionGlassOverlay(in: pdfView)
                self.updatePageNumber(in: pdfView)
            }

            DispatchQueue.main.async { [weak self, weak pdfView] in
                guard let self, let pdfView else { return }
                self.updatePageNumber(in: pdfView)
            }
        }

        // MARK: - Glass highlight overlay

        func repositionGlassOverlay(in pdfView: PDFView) {
            guard let match = currentHighlightMatch,
                  let page = match.pages.first else {
                glassOverlay?.isHidden = true
                return
            }

            let pageBounds = match.bounds(for: page)
            let viewRect = pdfView.convert(pageBounds, from: page)
            let padded = viewRect.insetBy(dx: -3, dy: -1)

            if !pdfView.bounds.intersects(padded) {
                glassOverlay?.isHidden = true
                return
            }

            if glassOverlay == nil {
                let view = UIView()
                view.backgroundColor = UIColor.tintColor.withAlphaComponent(0.18)
                view.layer.cornerRadius = 3
                pdfView.addSubview(view)
                glassOverlay = view
            }

            glassOverlay?.frame = padded
            glassOverlay?.isHidden = false
        }

        // MARK: - Page number tracking

        func updatePageNumber(in pdfView: PDFView) {
            guard let document = pdfView.document,
                  let page = pdfView.currentPage else { return }
            let pageIndex = document.index(for: page)
            if pageIndex != currentVisiblePage {
                currentVisiblePage = pageIndex
                onPageChange?(pageIndex + 1, document.pageCount)
            }
        }

        // MARK: - PDFPageOverlayViewProvider

        func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
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

            let allMatches = document.findString(firstWord, withOptions: .caseInsensitive)
            let pageMatches = allMatches.filter { match in
                match.pages.first.map { document.index(for: $0) } == pageIndex
            }

            var occurrence = 1
            if pageMatches.count > 1 {
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
#endif
