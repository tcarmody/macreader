import Foundation

// MARK: - Grouping Operations
extension AppState {

    func setGroupByMode(_ mode: GroupByMode) async {
        groupByMode = mode

        if mode == .date {
            serverGroupedArticles = []
        } else {
            await loadGroupedArticles()
        }
    }

    func loadGroupedArticles() async {
        guard groupByMode != .date else { return }

        isClusteringLoading = groupByMode == .topic
        error = nil

        do {
            let unreadOnly = selectedFilter == .unread
            let response = try await apiClient.getGroupedArticles(
                groupBy: groupByMode.rawValue,
                unreadOnly: unreadOnly
            )

            serverGroupedArticles = response.groups.map { group in
                ArticleGroup(
                    id: group.key,
                    title: group.label,
                    articles: group.articles
                )
            }

            articles = response.groups.flatMap { $0.articles }
        } catch {
            self.error = error.localizedDescription
            serverGroupedArticles = []
        }

        isClusteringLoading = false
    }

    internal func groupArticlesByDate(_ articles: [Article]) -> [ArticleGroup] {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: today)!

        var todayArticles: [Article] = []
        var yesterdayArticles: [Article] = []
        var lastWeekArticles: [Article] = []
        var olderArticles: [Article] = []

        for article in articles {
            let articleDate = article.publishedAt ?? article.createdAt

            if articleDate >= today {
                todayArticles.append(article)
            } else if articleDate >= yesterday {
                yesterdayArticles.append(article)
            } else if articleDate >= lastWeek {
                lastWeekArticles.append(article)
            } else {
                olderArticles.append(article)
            }
        }

        var groups: [ArticleGroup] = []

        if !todayArticles.isEmpty {
            groups.append(ArticleGroup(id: "today", title: "Today", articles: todayArticles))
        }
        if !yesterdayArticles.isEmpty {
            groups.append(ArticleGroup(id: "yesterday", title: "Yesterday", articles: yesterdayArticles))
        }
        if !lastWeekArticles.isEmpty {
            groups.append(ArticleGroup(id: "lastweek", title: "Last 7 Days", articles: lastWeekArticles))
        }
        if !olderArticles.isEmpty {
            groups.append(ArticleGroup(id: "older", title: "Older", articles: olderArticles))
        }

        return groups
    }
}
