import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Service for indexing articles in Spotlight for system-wide search
class SpotlightService {
    static let shared = SpotlightService()

    private let domainIdentifier = "com.datapointsai.articles"
    private let index = CSSearchableIndex.default()

    private init() {}

    // MARK: - Indexing

    /// Index a single article for Spotlight search
    /// - Parameter article: The article to index
    func indexArticle(_ article: Article, feedName: String? = nil) {
        let attributeSet = createAttributeSet(for: article, feedName: feedName)

        let item = CSSearchableItem(
            uniqueIdentifier: articleIdentifier(article.id),
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )

        // Articles expire from Spotlight after 30 days
        item.expirationDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())

        index.indexSearchableItems([item]) { error in
            if let error = error {
                print("Failed to index article \(article.id): \(error)")
            }
        }
    }

    /// Index a detailed article with full summary
    /// - Parameter article: The article detail to index
    func indexArticleDetail(_ article: ArticleDetail, feedName: String? = nil) {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)

        // Basic metadata
        attributeSet.title = article.title
        attributeSet.displayName = article.title
        attributeSet.contentURL = article.url

        // Content for search
        var searchableText = article.title
        if let summary = article.summaryFull {
            attributeSet.contentDescription = summary
            searchableText += " " + summary
        } else if let summary = article.summaryShort {
            attributeSet.contentDescription = summary
            searchableText += " " + summary
        }

        // Add key points to searchable text
        if let keyPoints = article.keyPoints {
            searchableText += " " + keyPoints.joined(separator: " ")
        }

        attributeSet.textContent = searchableText

        // Keywords from key points
        if let keyPoints = article.keyPoints {
            attributeSet.keywords = keyPoints
        }

        // Source/author
        if let feedName = feedName {
            attributeSet.creator = feedName
            attributeSet.publishers = [feedName]
        }

        // Dates
        if let publishedAt = article.publishedAt {
            attributeSet.contentCreationDate = publishedAt
            attributeSet.contentModificationDate = publishedAt
        }

        // Custom metadata
        attributeSet.identifier = String(article.id)
        attributeSet.relatedUniqueIdentifier = articleIdentifier(article.id)

        let item = CSSearchableItem(
            uniqueIdentifier: articleIdentifier(article.id),
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )

        item.expirationDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())

        index.indexSearchableItems([item]) { error in
            if let error = error {
                print("Failed to index article detail \(article.id): \(error)")
            }
        }
    }

    /// Index multiple articles at once
    /// - Parameter articles: Array of articles to index
    /// - Parameter feedNames: Dictionary mapping feed IDs to feed names
    func indexArticles(_ articles: [Article], feedNames: [Int: String] = [:]) {
        guard !articles.isEmpty else { return }

        let items = articles.map { article -> CSSearchableItem in
            let feedName = feedNames[article.feedId]
            let attributeSet = createAttributeSet(for: article, feedName: feedName)

            let item = CSSearchableItem(
                uniqueIdentifier: articleIdentifier(article.id),
                domainIdentifier: domainIdentifier,
                attributeSet: attributeSet
            )

            item.expirationDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())
            return item
        }

        index.indexSearchableItems(items) { error in
            if let error = error {
                print("Failed to batch index \(articles.count) articles: \(error)")
            }
        }
    }

    // MARK: - Removal

    /// Remove an article from Spotlight index
    /// - Parameter articleId: ID of the article to remove
    func removeArticle(_ articleId: Int) {
        index.deleteSearchableItems(withIdentifiers: [articleIdentifier(articleId)]) { error in
            if let error = error {
                print("Failed to remove article \(articleId) from index: \(error)")
            }
        }
    }

    /// Remove multiple articles from Spotlight index
    /// - Parameter articleIds: IDs of articles to remove
    func removeArticles(_ articleIds: [Int]) {
        let identifiers = articleIds.map { articleIdentifier($0) }
        index.deleteSearchableItems(withIdentifiers: identifiers) { error in
            if let error = error {
                print("Failed to remove \(articleIds.count) articles from index: \(error)")
            }
        }
    }

    /// Remove all articles for a specific feed
    /// - Parameter feedId: Feed ID whose articles should be removed
    func removeArticlesForFeed(_ feedId: Int) {
        // Since we don't have feed-based domain identifiers,
        // we need to track this differently or accept the limitation
        // For now, this would require knowing all article IDs for the feed
        print("Note: removeArticlesForFeed requires article ID tracking")
    }

    /// Remove all indexed articles
    func removeAllArticles() {
        index.deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { error in
            if let error = error {
                print("Failed to remove all articles from index: \(error)")
            }
        }
    }

    // MARK: - Helpers

    private func articleIdentifier(_ id: Int) -> String {
        return "\(domainIdentifier).\(id)"
    }

    private func createAttributeSet(for article: Article, feedName: String?) -> CSSearchableItemAttributeSet {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)

        // Basic metadata
        attributeSet.title = article.title
        attributeSet.displayName = article.title
        attributeSet.contentURL = article.url

        // Summary for search and display
        if let summary = article.summaryShort {
            attributeSet.contentDescription = summary
            attributeSet.textContent = "\(article.title) \(summary)"
        } else {
            attributeSet.textContent = article.title
        }

        // Source
        if let feedName = feedName {
            attributeSet.creator = feedName
            attributeSet.publishers = [feedName]
        }

        // Dates
        if let publishedAt = article.publishedAt {
            attributeSet.contentCreationDate = publishedAt
            attributeSet.contentModificationDate = publishedAt
        } else {
            attributeSet.contentCreationDate = article.createdAt
            attributeSet.contentModificationDate = article.createdAt
        }

        // Custom identifier for deep linking
        attributeSet.identifier = String(article.id)

        return attributeSet
    }

    // MARK: - Deep Link Handling

    /// Extract article ID from a Spotlight continuation activity
    /// - Parameter userActivity: The NSUserActivity from Spotlight
    /// - Returns: Article ID if found
    static func articleId(from userActivity: NSUserActivity) -> Int? {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
            return nil
        }

        // Extract ID from "com.datapointsai.articles.123" format
        let components = identifier.components(separatedBy: ".")
        if let lastComponent = components.last, let id = Int(lastComponent) {
            return id
        }

        return nil
    }
}
