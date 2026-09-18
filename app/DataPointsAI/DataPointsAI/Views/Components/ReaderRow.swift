import SwiftUI

/// One layout and density policy for every item in the middle column.
struct ReaderRow: View {
    let title: String
    let source: String
    var sourceSymbol: String? = nil
    let time: String
    let preview: String?
    let isRead: Bool
    let isBookmarked: Bool
    var isFeatured = false
    var hasSummary = false
    var hasRelated = false
    var hasChat = false
    @EnvironmentObject private var appState: AppState

    private var highlightedTitle: AttributedString {
        var result = AttributedString(title)
        let query = appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= AppState.minSearchQueryLength else { return result }
        var remaining = result.startIndex..<result.endIndex
        while let range = result[remaining].range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            result[range].underlineStyle = .single
            remaining = range.upperBound..<result.endIndex
        }
        return result
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(isRead ? Color.clear : Color.accentColor)
                .frame(width: 7, height: 7)
                .frame(width: 12, height: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(highlightedTitle)
                    .font(.headline)
                    .fontWeight(isRead ? .regular : .semibold)
                    .foregroundStyle(isRead ? .secondary : .primary)
                    .lineLimit(appState.settings.listDensity == .compact ? 1 : 2)
                HStack(spacing: 4) {
                    if let sourceSymbol { Image(systemName: sourceSymbol) }
                    Text(source).lineLimit(1)
                    Text("·")
                    Text(time).lineLimit(1)
                    Spacer(minLength: 4)
                    if isFeatured { Image(systemName: "star.fill").help("Featured") }
                    if isBookmarked { Image(systemName: "bookmark.fill").help("Bookmarked") }
                    if hasSummary { Image(systemName: "sparkles").help("Summary available") }
                    if hasRelated { Image(systemName: "link").help("Related articles available") }
                    if hasChat { Image(systemName: "bubble.left").help("Chat history") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if appState.settings.listDensity.showSummaryPreview, let preview, !preview.isEmpty {
                    Text(preview.smartQuotes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(appState.settings.listDensity == .spacious ? 3 : 2)
                }
            }
        }
        .padding(.vertical, appState.settings.listDensity.verticalPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, source, time, isRead ? "Read" : "Unread",
                             isBookmarked ? "Bookmarked" : nil, isFeatured ? "Featured" : nil,
                             hasSummary ? "Summary available" : nil, hasRelated ? "Related articles available" : nil,
                             hasChat ? "Chat history" : nil].compactMap { $0 }.joined(separator: ", "))
    }
}
