import SwiftUI
import WebKit
import Combine

/// Manages scroll state for the article detail view
@MainActor
class ArticleScrollState: ObservableObject {
    @Published var scrollPosition: CGFloat = 0
    @Published var contentHeight: CGFloat = 0
    @Published var viewHeight: CGFloat = 0
    @Published var scrollProxy: ScrollViewProxy?

    /// Whether we're at or near the bottom of the content
    var isAtBottom: Bool {
        guard contentHeight > viewHeight else { return true }
        let bottomThreshold: CGFloat = 50
        return scrollPosition >= (contentHeight - viewHeight - bottomThreshold)
    }

    /// Scroll down by approximately one screen
    func scrollDown() {
        // We'll use the scroll proxy to scroll to a marker
    }

    /// Reset scroll position when article changes
    func reset() {
        scrollPosition = 0
    }
}

/// Right pane: full article detail with summary
struct ArticleDetailView: View {
    @EnvironmentObject var appState: AppState
    @Binding var scrollState: ArticleScrollState
    @State private var isSummarizing: Bool = false
    @State private var isFetchingContent: Bool = false
    @State private var contentHeight: CGFloat = 200
    @State private var summarizationError: String?
    @State private var summarizationElapsed: Int = 0
    @State private var summarizationTimer: Timer?
    @Namespace private var scrollNamespace

    /// Current font size setting
    private var fontSize: ArticleFontSize {
        appState.settings.articleFontSize
    }

    /// Current line spacing setting
    private var lineSpacing: ArticleLineSpacing {
        appState.settings.articleLineSpacing
    }

    /// Current app typeface setting
    private var appTypeface: AppTypeface {
        appState.settings.appTypeface
    }

    /// Current content typeface setting
    private var contentTypeface: ContentTypeface {
        appState.settings.contentTypeface
    }

    var body: some View {
        Group {
            if let article = appState.selectedArticleDetail {
                GeometryReader { outerGeometry in
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                // Invisible anchor at top for scroll tracking
                                Color.clear
                                    .frame(height: 0)
                                    .id("top")

                                // Header
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(article.title)
                                        .font(appTypeface.font(size: fontSize.titleFontSize, weight: .bold))
                                        .lineSpacing(fontSize.titleFontSize * (lineSpacing.multiplier - 1))
                                        .textSelection(.enabled)

                            HStack(spacing: 8) {
                                if let feedName = feedName(for: article.feedId) {
                                    Text(feedName)
                                        .foregroundStyle(.secondary)
                                }
                                Text("·")
                                    .foregroundStyle(.secondary)
                                Text(article.timeAgo)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                // Bookmark indicator
                                if article.isBookmarked {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)
                                }
                            }
                            .font(.subheadline)
                        }

                        Divider()

                        // AI Summary
                        if let summary = article.summaryFull {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("AI Summary", systemImage: "sparkles")
                                    .font(appTypeface.font(size: fontSize.bodyFontSize + 2, weight: .semibold))
                                    .foregroundStyle(.blue)

                                Text(summary)
                                    .font(appTypeface.font(size: fontSize.bodyFontSize))
                                    .lineSpacing(fontSize.bodyFontSize * (lineSpacing.multiplier - 1))
                                    .textSelection(.enabled)
                            }
                            .padding()
                            .background(Color.blue.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            // No full summary - show generate button
                            VStack(spacing: 12) {
                                if isSummarizing {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Generating summary... \(summarizationElapsed)s")
                                        .foregroundStyle(.secondary)
                                    if summarizationElapsed > 10 {
                                        Text("Complex articles may take up to 60 seconds")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                } else if let error = summarizationError {
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                        Text(error)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Button("Retry") {
                                        startSummarization(articleId: article.id)
                                    }
                                    .buttonStyle(.bordered)
                                } else {
                                    if let shortSummary = article.summaryShort {
                                        Text(shortSummary)
                                            .font(appTypeface.font(size: fontSize.bodyFontSize))
                                            .lineSpacing(fontSize.bodyFontSize * (lineSpacing.multiplier - 1))
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("No summary available")
                                            .font(appTypeface.font(size: fontSize.bodyFontSize))
                                            .foregroundStyle(.secondary)
                                    }

                                    Button("Generate Summary") {
                                        startSummarization(articleId: article.id)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        // Key Points
                        if let keyPoints = article.keyPoints, !keyPoints.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Key Points")
                                    .font(appTypeface.font(size: fontSize.bodyFontSize + 2, weight: .semibold))

                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(keyPoints, id: \.self) { point in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("•")
                                                .font(appTypeface.font(size: fontSize.bodyFontSize))
                                                .foregroundStyle(.blue)
                                            Text(point)
                                                .font(appTypeface.font(size: fontSize.bodyFontSize))
                                                .lineSpacing(fontSize.bodyFontSize * (lineSpacing.multiplier - 1))
                                                .textSelection(.enabled)
                                        }
                                    }
                                }
                            }
                        }

                        Divider()

                        // Actions
                        HStack(spacing: 16) {
                            Button {
                                NSWorkspace.shared.open(article.originalUrl)
                            } label: {
                                Label("Read Original", systemImage: "safari")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                Task {
                                    try? await appState.toggleBookmark(articleId: article.id)
                                }
                            } label: {
                                Label(
                                    article.isBookmarked ? "Saved" : "Save",
                                    systemImage: article.isBookmarked ? "star.fill" : "star"
                                )
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            // Share button
                            ShareLink(item: article.originalUrl) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                        }

                        // Original content (rendered HTML)
                        if let content = article.content, !content.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Original Content")
                                        .font(appTypeface.font(size: fontSize.bodyFontSize + 2, weight: .semibold))

                                    Spacer()

                                    // For aggregator articles, offer to fetch full source content
                                    if article.sourceUrl != nil {
                                        if isFetchingContent {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                        } else {
                                            Button("Fetch Source Article") {
                                                Task {
                                                    isFetchingContent = true
                                                    try? await appState.fetchArticleContent(articleId: article.id)
                                                    isFetchingContent = false
                                                }
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                }

                                HTMLContentView(
                                    html: content,
                                    dynamicHeight: $contentHeight,
                                    fontSize: fontSize.bodyFontSize,
                                    lineHeight: lineSpacing.multiplier,
                                    fontFamily: contentTypeface.cssFontFamily
                                )
                                .frame(height: contentHeight)
                            }
                            .padding(.top, 8)
                        } else {
                            // No content - offer to fetch it
                            VStack(spacing: 12) {
                                if isFetchingContent {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Fetching content...")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Content not available in feed")
                                        .foregroundStyle(.secondary)

                                    Button("Fetch from Website") {
                                        Task {
                                            isFetchingContent = true
                                            try? await appState.fetchArticleContent(articleId: article.id)
                                            isFetchingContent = false
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                                // Invisible anchor at bottom for scroll tracking
                                Color.clear
                                    .frame(height: 0)
                                    .id("bottom")
                            }
                            .padding()
                            .background(
                                GeometryReader { contentGeometry in
                                    Color.clear
                                        .preference(
                                            key: ScrollOffsetPreferenceKey.self,
                                            value: -contentGeometry.frame(in: .named("scroll")).origin.y
                                        )
                                        .preference(
                                            key: ContentHeightPreferenceKey.self,
                                            value: contentGeometry.size.height
                                        )
                                }
                            )
                        }
                        .coordinateSpace(name: "scroll")
                        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                            scrollState.scrollPosition = value
                        }
                        .onPreferenceChange(ContentHeightPreferenceKey.self) { value in
                            scrollState.contentHeight = value
                        }
                        .onAppear {
                            scrollState.scrollProxy = proxy
                            scrollState.viewHeight = outerGeometry.size.height
                        }
                        .onChange(of: outerGeometry.size.height) { _, newValue in
                            scrollState.viewHeight = newValue
                        }
                        .onChange(of: article.id) { _, _ in
                            scrollState.reset()
                            proxy.scrollTo("top", anchor: .top)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Select an Article",
                    systemImage: "doc.text",
                    description: Text("Choose an article from the list to read its summary.")
                )
            }
        }
        .toolbar {
            if let article = appState.selectedArticleDetail {
                ToolbarItem {
                    Button {
                        if let selectedArticle = appState.selectedArticle {
                            Task {
                                let newStatus = !(appState.selectedArticleDetail?.isRead ?? false)
                                try? await appState.markRead(articleId: selectedArticle.id, isRead: newStatus)
                            }
                        }
                    } label: {
                        Label(
                            article.isRead ? "Mark as Unread" : "Mark as Read",
                            systemImage: article.isRead ? "envelope.open" : "envelope.badge"
                        )
                    }
                    .help(article.isRead ? "Mark as Unread" : "Mark as Read")
                }

                ToolbarItem {
                    Button {
                        if let selectedArticle = appState.selectedArticle {
                            Task {
                                try? await appState.toggleBookmark(articleId: selectedArticle.id)
                            }
                        }
                    } label: {
                        Label(
                            article.isBookmarked ? "Remove Bookmark" : "Bookmark",
                            systemImage: article.isBookmarked ? "star.fill" : "star"
                        )
                    }
                    .help(article.isBookmarked ? "Remove Bookmark" : "Bookmark")
                }

                ToolbarItem {
                    Button {
                        startSummarization(articleId: article.id)
                    } label: {
                        if isSummarizing {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 16, height: 16)
                        } else {
                            Label(
                                article.summaryFull != nil ? "Regenerate Summary" : "Generate Summary",
                                systemImage: article.summaryFull != nil ? "sparkles" : "sparkles.rectangle.stack"
                            )
                        }
                    }
                    .disabled(isSummarizing)
                    .help(article.summaryFull != nil ? "Regenerate Summary" : "Generate Summary")
                }
            }
        }
    }

    private func feedName(for feedId: Int) -> String? {
        appState.feeds.first { $0.id == feedId }?.name
    }

    private func startSummarization(articleId: Int) {
        summarizationError = nil
        summarizationElapsed = 0
        isSummarizing = true

        // Start elapsed time counter
        summarizationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            summarizationElapsed += 1
        }

        Task {
            do {
                try await appState.summarizeArticle(articleId: articleId)
                // Check if summary was actually generated for THIS article
                // (user may have navigated away during summarization)
                if appState.selectedArticleDetail?.id == articleId,
                   appState.selectedArticleDetail?.summaryFull == nil {
                    summarizationError = "Summary generation timed out. The server may be busy."
                }
            } catch {
                // Only show error if still viewing the same article
                if appState.selectedArticleDetail?.id == articleId {
                    summarizationError = error.localizedDescription
                }
            }

            summarizationTimer?.invalidate()
            summarizationTimer = nil
            isSummarizing = false
        }
    }
}

// MARK: - Preference Keys for Scroll Tracking

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    @Previewable @State var scrollState = ArticleScrollState()
    ArticleDetailView(scrollState: $scrollState)
        .environmentObject(AppState())
        .frame(width: 500, height: 600)
}
