import SwiftUI

/// Quick open overlay for fuzzy searching feeds and articles (Cmd+K)
struct QuickOpenView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var searchText: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.title3)

                TextField("Search feeds and articles...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isSearchFocused)
                    .onSubmit {
                        selectCurrentItem()
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Text("esc")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Results list
            if filteredResults.isEmpty {
                VStack(spacing: 8) {
                    if searchText.isEmpty {
                        Text("Type to search feeds and articles")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No results for \"\(searchText)\"")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            } else {
                ScrollViewReader { proxy in
                    List(selection: Binding(
                        get: { selectedIndex < filteredResults.count ? filteredResults[selectedIndex].id : nil },
                        set: { _ in }
                    )) {
                        // Feeds section
                        if !filteredFeeds.isEmpty {
                            Section("Feeds") {
                                ForEach(Array(filteredFeeds.enumerated()), id: \.element.id) { index, feed in
                                    QuickOpenFeedRow(feed: feed, isSelected: isSelected(item: .feed(feed)))
                                        .tag(QuickOpenItem.feed(feed).id)
                                        .id(QuickOpenItem.feed(feed).id)
                                        .onTapGesture {
                                            selectFeed(feed)
                                        }
                                }
                            }
                        }

                        // Articles section
                        if !filteredArticles.isEmpty {
                            Section("Articles") {
                                ForEach(Array(filteredArticles.enumerated()), id: \.element.id) { index, article in
                                    QuickOpenArticleRow(article: article, isSelected: isSelected(item: .article(article)))
                                        .tag(QuickOpenItem.article(article).id)
                                        .id(QuickOpenItem.article(article).id)
                                        .onTapGesture {
                                            selectArticle(article)
                                        }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: selectedIndex) { _, newIndex in
                        if newIndex < filteredResults.count {
                            withAnimation {
                                proxy.scrollTo(filteredResults[newIndex].id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 600, height: 400)
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onKeyPress(.return) {
            selectCurrentItem()
            return .handled
        }
    }

    // MARK: - Computed Properties

    private var filteredFeeds: [Feed] {
        guard !searchText.isEmpty else {
            return Array(appState.feeds.prefix(5))
        }
        let query = searchText.lowercased()
        return appState.feeds
            .filter { feed in
                feed.name.lowercased().contains(query) ||
                feed.url.absoluteString.lowercased().contains(query) ||
                (feed.category?.lowercased().contains(query) ?? false)
            }
            .prefix(10)
            .map { $0 }
    }

    private var filteredArticles: [Article] {
        guard !searchText.isEmpty else {
            return []
        }
        let query = searchText.lowercased()
        return appState.articles
            .filter { article in
                article.title.lowercased().contains(query) ||
                (article.summaryShort?.lowercased().contains(query) ?? false)
            }
            .prefix(10)
            .map { $0 }
    }

    private var filteredResults: [QuickOpenItem] {
        var results: [QuickOpenItem] = []
        results.append(contentsOf: filteredFeeds.map { .feed($0) })
        results.append(contentsOf: filteredArticles.map { .article($0) })
        return results
    }

    private func isSelected(item: QuickOpenItem) -> Bool {
        guard selectedIndex < filteredResults.count else { return false }
        return filteredResults[selectedIndex].id == item.id
    }

    // MARK: - Actions

    private func moveSelection(by delta: Int) {
        let newIndex = selectedIndex + delta
        if newIndex >= 0 && newIndex < filteredResults.count {
            selectedIndex = newIndex
        }
    }

    private func selectCurrentItem() {
        guard selectedIndex < filteredResults.count else { return }
        let item = filteredResults[selectedIndex]

        switch item {
        case .feed(let feed):
            selectFeed(feed)
        case .article(let article):
            selectArticle(article)
        }
    }

    private func selectFeed(_ feed: Feed) {
        appState.selectedFilter = .feed(feed.id)
        appState.deselectLibrary()
        Task {
            await appState.reloadArticles()
        }
        dismiss()
    }

    private func selectArticle(_ article: Article) {
        appState.selectedArticle = article
        appState.selectedArticleIds = [article.id]
        Task {
            await appState.loadArticleDetail(for: article)
        }
        dismiss()
    }
}

// MARK: - Supporting Types

enum QuickOpenItem: Identifiable {
    case feed(Feed)
    case article(Article)

    var id: String {
        switch self {
        case .feed(let feed): return "feed-\(feed.id)"
        case .article(let article): return "article-\(article.id)"
        }
    }
}

// MARK: - Row Views

struct QuickOpenFeedRow: View {
    let feed: Feed
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.up.forward")
                .foregroundStyle(.blue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(feed.name)
                    .fontWeight(.medium)

                if let category = feed.category {
                    Text(category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if feed.unreadCount > 0 {
                Text("\(feed.unreadCount)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
    }
}

struct QuickOpenArticleRow: View {
    let article: Article
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: article.isRead ? "doc.text" : "doc.text.fill")
                .foregroundStyle(article.isRead ? .secondary : .primary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(article.title)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let summary = article.summaryShort {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if article.isBookmarked {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
    }
}

#Preview {
    QuickOpenView()
        .environmentObject(AppState())
        .padding(40)
        .background(.black.opacity(0.5))
}
