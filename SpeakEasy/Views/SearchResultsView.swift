import SwiftUI

/// Search results sidebar — list of search hits with highlighted snippets.
struct SearchResultsView: View {
    let searchQuery: String
    let searchResults: [SearchResult]
    let onResultSelected: (SearchResult) -> Void

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
                            Text(Self.highlightedSnippet(result.snippet, query: searchQuery))
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

    static func highlightedSnippet(_ snippet: String, query: String) -> AttributedString {
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
}
