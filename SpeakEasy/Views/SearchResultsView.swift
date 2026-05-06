import PDFKit
import SwiftUI

/// Search results sidebar — list of search hits with longer snippets, a page-number
/// badge, and a small page-thumbnail screenshot showing where on the PDF the match
/// lives (with a yellow box drawn over the match itself).
struct SearchResultsView: View {
    let searchQuery: String
    let searchResults: [SearchResult]
    let pdfDocument: PDFDocument?
    /// Per-page list of bounds rects in PDF page coordinates, in document order.
    let pdfMatchBoundsByPage: [Int: [CGRect]]
    let onResultSelected: (SearchResult) -> Void

    @StateObject private var thumbnailCache = SearchThumbnailCache()

    var body: some View {
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
                            onResultSelected(result)
                        } label: {
                            SearchResultRow(
                                result: result,
                                searchQuery: searchQuery,
                                pdfDocument: pdfDocument,
                                pageBounds: result.pageNumber.flatMap { pdfMatchBoundsByPage[$0] } ?? [],
                                cache: thumbnailCache
                            )
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

    static func highlightedSnippet(_ snippet: String, query: String) -> AttributedString {
        var attributed = AttributedString(snippet)
        let lowerSnippet = snippet.lowercased()
        let lowerQuery = query.lowercased()
        guard !lowerQuery.isEmpty else { return attributed }
        var searchStart = lowerSnippet.startIndex

        while let range = lowerSnippet.range(of: lowerQuery, range: searchStart..<lowerSnippet.endIndex) {
            if let attrStart = AttributedString.Index(range.lowerBound, within: attributed),
               let attrEnd = AttributedString.Index(range.upperBound, within: attributed) {
                attributed[attrStart..<attrEnd].font = .system(size: 13, weight: .bold)
                attributed[attrStart..<attrEnd].foregroundColor = .accentColor
            }
            searchStart = range.upperBound
        }

        return attributed
    }
}

// MARK: - Result row

private struct SearchResultRow: View {
    let result: SearchResult
    let searchQuery: String
    let pdfDocument: PDFDocument?
    /// Bounds rects for *all* matches on this page, in document order. The row
    /// picks the (pageOccurrence)-th rect for its highlight overlay.
    let pageBounds: [CGRect]
    @ObservedObject var cache: SearchThumbnailCache

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let pageNumber = result.pageNumber, let page = page(at: pageNumber) {
                SearchThumbnailView(
                    page: page,
                    pageNumber: pageNumber,
                    occurrence: result.pageOccurrence,
                    pageBounds: pageBounds,
                    searchQuery: searchQuery,
                    cache: cache
                )
                .frame(width: 72)
            }

            VStack(alignment: .leading, spacing: 5) {
                if let pageNumber = result.pageNumber {
                    pageBadge(pageNumber: pageNumber)
                }
                Text(SearchResultsView.highlightedSnippet(result.snippet, query: searchQuery))
                    .font(.system(size: 13))
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 1)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func page(at pageNumber: Int) -> PDFPage? {
        guard let doc = pdfDocument else { return nil }
        let idx = pageNumber - 1
        guard idx >= 0, idx < doc.pageCount else { return nil }
        return doc.page(at: idx)
    }

    private func pageBadge(pageNumber: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text")
                .font(.system(size: 9, weight: .semibold))
            Text("Page \(pageNumber)")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.accentColor))
    }
}

// MARK: - Thumbnail

private struct SearchThumbnailView: View {
    let page: PDFPage
    let pageNumber: Int
    let occurrence: Int
    let pageBounds: [CGRect]
    let searchQuery: String
    @ObservedObject var cache: SearchThumbnailCache

    private var cacheKey: String {
        "p\(pageNumber)|q\(searchQuery.lowercased())"
    }

    private var pdfPageBounds: CGRect { page.bounds(for: .mediaBox) }

    private var aspect: CGFloat {
        guard pdfPageBounds.width > 0, pdfPageBounds.height > 0 else { return 0.77 }
        return pdfPageBounds.width / pdfPageBounds.height
    }

    /// Normalized rect (0..1) in top-down image coordinates for the highlight overlay.
    /// `nil` if no bounds exist for this occurrence.
    private var highlightNormalizedRect: CGRect? {
        guard occurrence >= 1, pageBounds.indices.contains(occurrence - 1) else { return nil }
        let pdfRect = pageBounds[occurrence - 1]
        guard pdfPageBounds.width > 0, pdfPageBounds.height > 0 else { return nil }
        // PDFKit uses bottom-left origin; SwiftUI/raster images use top-left.
        return CGRect(
            x: pdfRect.minX / pdfPageBounds.width,
            y: 1 - (pdfRect.minY + pdfRect.height) / pdfPageBounds.height,
            width: pdfRect.width / pdfPageBounds.width,
            height: pdfRect.height / pdfPageBounds.height
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let image = cache.images[cacheKey] {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .accessibilityLabel("Page \(pageNumber) thumbnail")
            } else {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        ProgressView()
                            .controlSize(.small)
                    )
                    .aspectRatio(aspect, contentMode: .fit)
            }

            if let normalized = highlightNormalizedRect {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.yellow.opacity(0.40))
                        .overlay(Rectangle().stroke(Color.orange, lineWidth: 1))
                        .frame(
                            width: max(3, normalized.width * geo.size.width),
                            height: max(3, normalized.height * geo.size.height)
                        )
                        .offset(
                            x: normalized.minX * geo.size.width,
                            y: normalized.minY * geo.size.height
                        )
                }
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.primary.opacity(0.18), lineWidth: 0.5)
        )
        .task(id: cacheKey) {
            guard cache.images[cacheKey] == nil else { return }
            // PDFKit thumbnail rendering is main-thread; yield first so the row
            // can lay out (and the placeholder appear) before we block on render.
            await Task.yield()
            let rendered = SearchThumbnailView.renderThumbnail(of: page)
            cache.set(cacheKey, rendered)
        }
    }

    private static func renderThumbnail(of page: PDFPage) -> PlatformImage {
        let bounds = page.bounds(for: .mediaBox)
        let safeWidth = max(bounds.width, 1)
        let safeHeight = max(bounds.height, 1)
        let aspect = safeHeight / safeWidth
        // Render at ~2× the on-screen size for retina sharpness.
        let targetWidth: CGFloat = 200
        let size = CGSize(width: targetWidth, height: targetWidth * aspect)
        return page.thumbnail(of: size, for: .mediaBox)
    }
}

// MARK: - Cache

@MainActor
final class SearchThumbnailCache: ObservableObject {
    @Published var images: [String: PlatformImage] = [:]

    func set(_ key: String, _ image: PlatformImage) {
        images[key] = image
    }

    func clear() {
        images.removeAll()
    }
}
