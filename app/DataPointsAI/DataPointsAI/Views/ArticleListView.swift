import SwiftUI

/// Middle pane: article list with multi-select support
struct ArticleListView: View {
    @EnvironmentObject var appState: AppState
    @State private var listSelection: Set<Article.ID> = []

    var body: some View {
        Group {
            if appState.isLoading && appState.articles.isEmpty {
                ProgressView("Loading articles...")
            } else if appState.isClusteringLoading {
                ProgressView("Clustering by topic...")
            } else if appState.groupedArticles.isEmpty {
                EmptyArticlesView()
            } else {
                articleList
            }
        }
        .navigationTitle(appState.currentFilterName)
        .onChange(of: listSelection) { oldSelection, newSelection in
            handleSelectionChange(from: oldSelection, to: newSelection)
        }
        .refreshable {
            try? await appState.refreshFeeds()
        }
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                Picker("Group By", selection: Binding(
                    get: { appState.groupByMode },
                    set: { newMode in
                        Task {
                            await appState.setGroupByMode(newMode)
                        }
                    }
                )) {
                    ForEach(GroupByMode.allCases, id: \.self) { mode in
                        Label(mode.label, systemImage: mode.iconName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Group articles by \(appState.groupByMode.label)")
            }

            ToolbarItemGroup {
                if !appState.selectedArticleIds.isEmpty {
                    selectionToolbar
                }

                // Hide read toggle
                Button {
                    appState.hideReadArticles.toggle()
                } label: {
                    Image(systemName: appState.hideReadArticles ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .help(appState.hideReadArticles ? "Show Read Articles" : "Hide Read Articles")

                // Sort menu
                Menu {
                    ForEach(ArticleSortOption.allCases, id: \.self) { option in
                        Button {
                            appState.sortOption = option
                        } label: {
                            HStack {
                                if appState.sortOption == option {
                                    Image(systemName: "checkmark")
                                }
                                Label(option.label, systemImage: option.iconName)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
                .help("Sort: \(appState.sortOption.label)")

                // More actions menu
                Menu {
                    Button {
                        Task {
                            try? await markCurrentFilterRead()
                        }
                    } label: {
                        Label("Mark All as Read", systemImage: "checkmark.circle")
                    }

                    Divider()

                    if !appState.selectedArticleIds.isEmpty {
                        Button {
                            appState.selectedArticleIds.removeAll()
                            listSelection.removeAll()
                        } label: {
                            Label("Clear Selection", systemImage: "xmark.circle")
                        }
                    }

                    Button {
                        selectAllVisible()
                    } label: {
                        Label("Select All", systemImage: "checkmark.circle.fill")
                    }
                    .keyboardShortcut("a", modifiers: [.command])
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("More Actions")
            }
        }
    }

    private var articleList: some View {
        List(selection: $listSelection) {
            ForEach(appState.groupedArticles) { group in
                Section {
                    ForEach(group.articles) { article in
                        ArticleRow(
                            article: article,
                            isMultiSelected: appState.selectedArticleIds.contains(article.id)
                        )
                        .tag(article.id)
                    }
                } header: {
                    GroupSectionHeader(
                        group: group,
                        groupByMode: appState.groupByMode,
                        groupIndex: appState.groupedArticles.firstIndex(where: { $0.id == group.id }) ?? 0
                    )
                }
            }
        }
        .listStyle(.inset)
    }

    private func handleSelectionChange(from oldSelection: Set<Article.ID>, to newSelection: Set<Article.ID>) {
        // Sync list selection to app state
        appState.selectedArticleIds = newSelection

        // If exactly one item is selected, load its detail
        if newSelection.count == 1, let selectedId = newSelection.first {
            let allArticles = appState.groupedArticles.flatMap { $0.articles }
            if let article = allArticles.first(where: { $0.id == selectedId }) {
                appState.selectedArticle = article
                Task {
                    await appState.loadArticleDetail(for: article)
                }
            }
        } else if newSelection.isEmpty {
            appState.selectedArticle = nil
        }
    }

    @ViewBuilder
    private var selectionToolbar: some View {
        let count = appState.selectedArticleIds.count

        Button {
            Task {
                try? await appState.bulkMarkRead(articleIds: Array(appState.selectedArticleIds), isRead: true)
                appState.selectedArticleIds.removeAll()
            }
        } label: {
            Image(systemName: "envelope.open")
        }
        .help("Mark \(count) as Read")

        Button {
            Task {
                try? await appState.bulkMarkRead(articleIds: Array(appState.selectedArticleIds), isRead: false)
                appState.selectedArticleIds.removeAll()
            }
        } label: {
            Image(systemName: "envelope.badge")
        }
        .help("Mark \(count) as Unread")

        Button {
            appState.selectedArticleIds.removeAll()
        } label: {
            Image(systemName: "xmark.circle")
        }
        .help("Clear Selection (\(count))")
    }

    private func selectAllVisible() {
        let allIds = appState.groupedArticles.flatMap { $0.articles }.map { $0.id }
        listSelection = Set(allIds)
        appState.selectedArticleIds = Set(allIds)
    }

    private func markCurrentFilterRead() async throws {
        switch appState.selectedFilter {
        case .all:
            try await appState.markAllRead()
        case .unread:
            try await appState.markAllRead()
        case .today, .bookmarked, .summarized, .unsummarized:
            // Mark all visible articles in this filter as read
            let ids = appState.filteredArticles.map { $0.id }
            try await appState.bulkMarkRead(articleIds: ids)
        case .feed(let feedId):
            try await appState.markFeedRead(feedId: feedId)
        }
    }
}

/// Empty state when no articles with custom illustrations
struct EmptyArticlesView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            emptyStateIllustration
                .frame(width: 120, height: 120)

            VStack(spacing: 8) {
                Text(emptyTitle)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(emptyDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            if appState.feeds.isEmpty {
                Button("Add Feed") {
                    DispatchQueue.main.async {
                        appState.showAddFeed = true
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Refresh") {
                    Task {
                        try? await appState.refreshFeeds()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyStateIllustration: some View {
        switch appState.selectedFilter {
        case .all:
            if appState.feeds.isEmpty {
                NoFeedsIllustration()
            } else {
                NoArticlesIllustration()
            }
        case .unread:
            AllCaughtUpIllustration()
        case .today:
            NothingTodayIllustration()
        case .bookmarked:
            NoBookmarksIllustration()
        case .summarized, .unsummarized:
            SparklesIllustration()
        case .feed:
            NoArticlesIllustration()
        }
    }

    private var emptyTitle: String {
        switch appState.selectedFilter {
        case .all:
            return appState.feeds.isEmpty ? "No Feeds" : "No Articles"
        case .unread:
            return "All Caught Up"
        case .today:
            return "Nothing New Today"
        case .bookmarked:
            return "No Saved Articles"
        case .summarized:
            return "No Summarized Articles"
        case .unsummarized:
            return "No Unsummarized Articles"
        case .feed:
            return "No Articles"
        }
    }

    private var emptyDescription: String {
        switch appState.selectedFilter {
        case .all:
            return appState.feeds.isEmpty
                ? "Add some feeds to get started."
                : "No articles found."
        case .unread:
            return "You've read all your articles."
        case .today:
            return "No articles published today yet."
        case .bookmarked:
            return "Bookmark articles to save them for later."
        case .summarized:
            return "Articles with AI summaries will appear here."
        case .unsummarized:
            return "All articles have been summarized."
        case .feed:
            return "This feed has no articles yet."
        }
    }
}

// MARK: - Empty State Illustrations

/// Illustration for "No Feeds" state - stack of empty documents
struct NoFeedsIllustration: View {
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(Color.blue.opacity(0.1))

            // Stack of papers
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 50, height: 60)
                .offset(x: 8, y: 8)
                .rotationEffect(.degrees(5))

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.4))
                .frame(width: 50, height: 60)
                .offset(x: 4, y: 4)
                .rotationEffect(.degrees(2))

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white)
                .frame(width: 50, height: 60)
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)

            // Plus sign
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.blue)
                .offset(x: 20, y: 20)
        }
    }
}

/// Illustration for "No Articles" state - empty document
struct NoArticlesIllustration: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.1))

            // Document shape
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white)
                .frame(width: 55, height: 70)
                .shadow(color: .black.opacity(0.1), radius: 3, y: 2)

            // Lines representing text
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 35, height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 30, height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 35, height: 4)
            }
            .offset(y: -5)
        }
    }
}

/// Illustration for "All Caught Up" state - checkmark celebration
struct AllCaughtUpIllustration: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.1))

            // Checkmark circle
            Circle()
                .fill(Color.green.opacity(0.2))
                .frame(width: 60, height: 60)

            Image(systemName: "checkmark")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.green)

            // Celebration dots
            ForEach(0..<6, id: \.self) { i in
                Circle()
                    .fill(Color.green.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .offset(y: -50)
                    .rotationEffect(.degrees(Double(i) * 60))
            }
        }
    }
}

/// Illustration for "Nothing Today" state - calendar/sun
struct NothingTodayIllustration: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.orange.opacity(0.1))

            // Sun rays
            ForEach(0..<8, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.orange.opacity(0.4))
                    .frame(width: 4, height: 12)
                    .offset(y: -40)
                    .rotationEffect(.degrees(Double(i) * 45))
            }

            // Sun center
            Circle()
                .fill(Color.orange.opacity(0.3))
                .frame(width: 50, height: 50)

            // Sleeping face
            Text("z")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.orange)
                .offset(x: 20, y: -15)

            Text("z")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.orange.opacity(0.7))
                .offset(x: 28, y: -25)
        }
    }
}

/// Illustration for "No Bookmarks" state - empty star
struct NoBookmarksIllustration: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.yellow.opacity(0.1))

            // Star outline
            Image(systemName: "star")
                .font(.system(size: 50))
                .foregroundStyle(Color.yellow.opacity(0.4))

            // Dashed circle
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                .foregroundStyle(Color.yellow.opacity(0.3))
                .frame(width: 80, height: 80)
        }
    }
}

/// Illustration for summarized/unsummarized states - sparkles
struct SparklesIllustration: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.purple.opacity(0.1))

            // Large sparkle
            Image(systemName: "sparkle")
                .font(.system(size: 40))
                .foregroundStyle(.purple.opacity(0.6))

            // Small sparkles around
            Image(systemName: "sparkle")
                .font(.system(size: 16))
                .foregroundStyle(.purple.opacity(0.4))
                .offset(x: 30, y: -20)

            Image(systemName: "sparkle")
                .font(.system(size: 12))
                .foregroundStyle(.purple.opacity(0.3))
                .offset(x: -25, y: 25)

            Image(systemName: "sparkle")
                .font(.system(size: 14))
                .foregroundStyle(.purple.opacity(0.35))
                .offset(x: -30, y: -15)
        }
    }
}

/// Section header for article groups with visual customization based on group type
struct GroupSectionHeader: View {
    let group: ArticleGroup
    let groupByMode: GroupByMode
    let groupIndex: Int

    /// Colors for topic clusters
    private static let topicColors: [Color] = [
        .blue, .purple, .pink, .orange, .green, .teal, .indigo, .mint, .cyan, .red
    ]

    /// Get color for topic cluster based on index
    private var topicColor: Color {
        Self.topicColors[groupIndex % Self.topicColors.count]
    }

    /// Icon for the group based on mode
    private var groupIcon: String {
        switch groupByMode {
        case .date:
            switch group.id {
            case "today": return "sun.max.fill"
            case "yesterday": return "moon.fill"
            case "lastweek": return "calendar"
            default: return "clock"
            }
        case .feed:
            return "newspaper.fill"
        case .topic:
            return "sparkles"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Icon with color based on mode
            Group {
                if groupByMode == .topic {
                    // Topic clusters get colored badges
                    Image(systemName: groupIcon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(topicColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: groupIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Title
            Text(group.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(groupByMode == .topic ? topicColor : .primary)

            // Article count badge
            Text("\(group.articles.count)")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(groupByMode == .topic ? .white : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    groupByMode == .topic
                        ? topicColor.opacity(0.8)
                        : Color.secondary.opacity(0.15)
                )
                .clipShape(Capsule())

            Spacer()

            // Unread count for the group
            let unreadCount = group.articles.filter { !$0.isRead }.count
            if unreadCount > 0 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                    Text("\(unreadCount) unread")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ArticleListView()
        .environmentObject(AppState())
        .frame(width: 350)
}
