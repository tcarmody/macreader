import SwiftUI

enum DetailTab: String, CaseIterable {
    case article = "Content"
    case ai = "Summary"
    case related = "Related"
    case chat = "Chat"
}

enum ReaderCommand {
    case extract, extractAuthenticated, login, summarize, findRelated, promote, delete
}

/// Presentation data shared by feed articles and privately saved documents.
/// Origin controls capabilities; the underlying API models remain separate.
struct ReaderItem: Identifiable {
    enum Origin { case feed, library }
    let origin: Origin
    let itemID: Int
    var id: String { "\(origin)-\(itemID)" }
    let title: String
    let source: String
    let sourceSymbol: String
    let date: Date
    let url: URL?
    let content: String?
    let isHTML: Bool
    let summaryShort: String?
    let summaryFull: String?
    let keyPoints: [String]
    let relatedLinks: [RelatedLink]
    let relatedLinksError: String?
    let isRead: Bool
    let isBookmarked: Bool
    let isFeatured: Bool
    let featuredNote: String?
    let isPromoted: Bool
    let readTime: String?

    init(article: ArticleDetail, source: String) {
        origin = .feed
        itemID = article.id
        title = article.displayTitle
        self.source = source
        sourceSymbol = "dot.radiowaves.up.forward"
        date = article.publishedAt ?? article.createdAt
        url = article.originalUrl
        content = article.content
        isHTML = true
        summaryShort = article.summaryShort
        summaryFull = article.summaryFull
        keyPoints = article.keyPoints ?? []
        relatedLinks = article.relatedLinks ?? []
        relatedLinksError = article.relatedLinksError
        isRead = article.isRead
        isBookmarked = article.isBookmarked
        isFeatured = article.isFeatured
        featuredNote = article.featuredNote
        isPromoted = article.promotedToComposer != nil
        readTime = article.estimatedReadTime
    }

    init(libraryItem: LibraryItemDetail) {
        origin = .library
        itemID = libraryItem.id
        title = libraryItem.displayName
        source = libraryItem.type == .url
            ? (libraryItem.url.host ?? libraryItem.type.label) : libraryItem.type.label
        sourceSymbol = libraryItem.type.iconName
        date = libraryItem.createdAt
        url = libraryItem.type == .url ? libraryItem.url : nil
        content = libraryItem.content
        isHTML = libraryItem.type == .url || libraryItem.type == .html
        summaryShort = libraryItem.summaryShort
        summaryFull = libraryItem.summaryFull
        keyPoints = libraryItem.keyPoints ?? []
        relatedLinks = libraryItem.relatedLinks ?? []
        relatedLinksError = libraryItem.relatedLinksError
        isRead = libraryItem.isRead
        isBookmarked = libraryItem.isBookmarked
        isFeatured = false
        featuredNote = nil
        isPromoted = libraryItem.promotedToComposer != nil
        let words = libraryItem.content?.split(whereSeparator: { $0.isWhitespace }).count ?? 0
        readTime = words > 0 ? "\(max(1, words / 250)) min read" : nil
    }

    /// Render extracted document text with the same scalable, single-scroll
    /// reader as HTML, while preserving literal text and paragraph breaks.
    var renderedContent: String {
        let text = content ?? ""
        guard !isHTML else { return text }
        let escaped = text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return "<div style=\"white-space: pre-wrap\">\(escaped)</div>"
    }

    var shareText: String {
        [title, summaryFull ?? summaryShort, source, url?.absoluteString]
            .compactMap { $0 }.joined(separator: "\n\n")
    }
}
