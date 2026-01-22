import SwiftUI

/// Middle pane: newsletters organized by sender (similar to RSS feeds)
struct NewslettersView: View {
    @EnvironmentObject var appState: AppState
    @State private var listSelection: Set<Int> = []  // Article IDs

    var body: some View {
        Group {
            if appState.isLoading && appState.newsletterFeeds.isEmpty {
                ProgressView("Loading newsletters...")
            } else if appState.newsletterFeeds.isEmpty {
                EmptyNewslettersView()
            } else if let selectedFeed = appState.selectedNewsletterFeed {
                // Show articles for selected newsletter feed
                newsletterArticleList(for: selectedFeed)
            } else {
                // Show all newsletter feeds
                allNewsletterFeedsList
            }
        }
        .navigationTitle(appState.selectedNewsletterFeed?.name ?? "Newsletters")
        .onChange(of: listSelection) { oldSelection, newSelection in
            handleSelectionChange(from: oldSelection, to: newSelection)
        }
        .toolbar {
            ToolbarItemGroup {
                if appState.selectedNewsletterFeed != nil {
                    // Back button when viewing a specific feed
                    Button {
                        appState.deselectNewsletterFeed()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .help("Back to All Newsletters")
                }

                // Refresh newsletters (triggers Gmail fetch)
                Button {
                    Task {
                        try? await appState.refreshFeeds()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Newsletters")

                // Open settings
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Image(systemName: "gear")
                }
                .help("Newsletter Settings")
            }
        }
    }

    // MARK: - All Newsletter Feeds List

    private var allNewsletterFeedsList: some View {
        List {
            ForEach(appState.newsletterFeeds) { feed in
                NewsletterFeedRow(feed: feed)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task {
                            await appState.selectNewsletterFeed(feed)
                        }
                    }
                    .contextMenu {
                        feedContextMenu(for: feed)
                    }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Newsletter Articles List

    private func newsletterArticleList(for feed: Feed) -> some View {
        Group {
            if appState.newsletterArticles.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "envelope.open")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No newsletters from \(feed.name)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $listSelection) {
                    ForEach(appState.newsletterArticles) { article in
                        NewsletterArticleRow(article: article)
                            .tag(article.id)
                            .contextMenu {
                                articleContextMenu(for: article)
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Selection Handling

    private func handleSelectionChange(from oldSelection: Set<Int>, to newSelection: Set<Int>) {
        // If exactly one article is selected, load its detail
        if newSelection.count == 1, let selectedId = newSelection.first {
            if let article = appState.newsletterArticles.first(where: { $0.id == selectedId }) {
                Task {
                    await appState.loadNewsletterArticleDetail(for: article)
                }
            }
        } else if newSelection.isEmpty {
            appState.selectedArticle = nil
            appState.selectedArticleDetail = nil
        }
    }

    // MARK: - Context Menus

    @ViewBuilder
    private func feedContextMenu(for feed: Feed) -> some View {
        Button {
            Task {
                try? await appState.markFeedRead(feedId: feed.id)
            }
        } label: {
            Label("Mark All as Read", systemImage: "checkmark.circle")
        }

        Divider()

        Button(role: .destructive) {
            Task {
                try? await appState.deleteFeed(feedId: feed.id)
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func articleContextMenu(for article: Article) -> some View {
        Button {
            Task {
                try? await appState.toggleBookmark(articleId: article.id)
            }
        } label: {
            Label(article.isBookmarked ? "Remove Bookmark" : "Bookmark", systemImage: article.isBookmarked ? "star.fill" : "star")
        }

        Button {
            Task {
                try? await appState.markRead(articleId: article.id, isRead: !article.isRead)
            }
        } label: {
            Label(article.isRead ? "Mark as Unread" : "Mark as Read", systemImage: article.isRead ? "envelope.badge" : "envelope.open")
        }

        Divider()

        Button {
            Task {
                try? await appState.summarizeArticle(articleId: article.id)
            }
        } label: {
            Label("Summarize", systemImage: "sparkles")
        }
    }
}

/// Row for a newsletter feed (sender)
struct NewsletterFeedRow: View {
    let feed: Feed
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            // Newsletter icon
            Image(systemName: "envelope.open")
                .font(.title2)
                .foregroundStyle(feed.unreadCount > 0 ? Color.orange : Color.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(feed.name)
                    .font(appState.settings.listDensity == .compact ? .subheadline : .headline)
                    .fontWeight(feed.unreadCount > 0 ? .semibold : .regular)
                    .foregroundStyle(feed.unreadCount > 0 ? .primary : .secondary)
                    .lineLimit(1)

                // Extract sender email from URL for subtitle
                if let senderEmail = extractSenderEmail(from: feed.url) {
                    Text(senderEmail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Unread count badge
            if feed.unreadCount > 0 {
                Text("\(feed.unreadCount)")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.orange)
                    .clipShape(Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, appState.settings.listDensity == .compact ? 4 : 8)
        .contentShape(Rectangle())
    }

    private func extractSenderEmail(from url: URL) -> String? {
        // URL format: newsletter://sender@example.com
        let urlString = url.absoluteString
        if urlString.hasPrefix("newsletter://") {
            return String(urlString.dropFirst("newsletter://".count))
        }
        return nil
    }
}

/// Row for a newsletter article
struct NewsletterArticleRow: View {
    let article: Article
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            // Read indicator
            Circle()
                .fill(article.isRead ? Color.clear : Color.orange)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                // Title (subject line)
                Text(article.title)
                    .font(appState.settings.listDensity == .compact ? .subheadline : .headline)
                    .fontWeight(article.isRead ? .regular : .semibold)
                    .foregroundStyle(article.isRead ? .secondary : .primary)
                    .lineLimit(appState.settings.listDensity == .compact ? 1 : 2)

                // Summary preview if available
                if let summary = article.summaryShort, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(appState.settings.listDensity == .compact ? 1 : 2)
                }

                // Metadata row
                HStack(spacing: 8) {
                    Text(article.timeAgo)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if article.isBookmarked {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }

                    if article.summaryShort != nil {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, appState.settings.listDensity == .compact ? 4 : 8)
        .contentShape(Rectangle())
    }
}

/// Empty state for newsletters
struct EmptyNewslettersView: View {
    var body: some View {
        VStack(spacing: 24) {
            // Newsletter illustration
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 120, height: 120)

                // Envelope stack
                ZStack {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange.opacity(0.4))
                        .offset(x: 8, y: 8)

                    Image(systemName: "envelope.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange.opacity(0.6))
                        .offset(x: 4, y: 4)

                    Image(systemName: "envelope.open.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                }
            }

            VStack(spacing: 8) {
                Text("No Newsletters")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Set up Gmail integration to automatically import newsletter emails for reading and summarization.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            Button {
                // Open settings to newsletter section
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Label("Set Up Newsletters", systemImage: "gear")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NewslettersView()
        .environmentObject(AppState())
        .frame(width: 350)
}
