import SwiftUI
import WebKit
import Combine

/// Manages scroll state for the article detail view
/// Uses ScrollViewProxy for reliable scroll-to-top and NSScrollView for page up/down
@MainActor
class ArticleScrollState: ObservableObject {
    /// Reference to the underlying NSScrollView (set by ScrollViewAccessor)
    weak var scrollView: NSScrollView?

    /// ScrollViewProxy for reliable scroll-to-top (set by ArticleDetailView)
    var scrollProxy: ScrollViewProxy?

    /// ID for the top anchor element
    static let topAnchorID = "article-top"

    /// Current scroll progress (0.0 to 1.0)
    @Published var scrollProgress: CGFloat = 0

    /// Observer for scroll position changes
    private var scrollObserver: NSObjectProtocol?

    /// Whether we can scroll down (content below visible area)
    var canScrollDown: Bool {
        guard let scrollView = scrollView else { return false }
        let clipView = scrollView.contentView
        let documentView = scrollView.documentView

        guard let docView = documentView else { return false }

        let contentHeight = docView.frame.height
        let viewHeight = clipView.bounds.height
        let currentY = clipView.bounds.origin.y

        // Can scroll if there's content below the visible area
        return currentY + viewHeight < contentHeight - 1
    }

    /// Whether we can scroll up (content above visible area)
    var canScrollUp: Bool {
        guard let scrollView = scrollView else { return false }
        let clipView = scrollView.contentView
        return clipView.bounds.origin.y > 1
    }

    /// Scroll down by one page using NSScrollView's built-in method
    func scrollDown() {
        guard let scrollView = scrollView else {
            print("scrollDown: No scroll view!")
            return
        }

        // Use NSScrollView's pageDown which handles everything correctly
        scrollView.pageDown(nil)
    }

    /// Scroll up by one page using NSScrollView's built-in method
    func scrollUp() {
        guard let scrollView = scrollView else {
            print("scrollUp: No scroll view!")
            return
        }

        // Use NSScrollView's pageUp which handles everything correctly
        scrollView.pageUp(nil)
    }

    /// Reset scroll position to top using ScrollViewProxy
    func scrollToTop() {
        scrollProxy?.scrollTo(Self.topAnchorID, anchor: .top)
        scrollProgress = 0
    }

    /// Start observing scroll position changes
    func startObservingScroll() {
        guard scrollObserver == nil else { return }

        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView?.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.updateScrollProgress()
        }

        // Enable bounds change notifications
        scrollView?.contentView.postsBoundsChangedNotifications = true
    }

    /// Stop observing scroll position
    func stopObservingScroll() {
        if let observer = scrollObserver {
            NotificationCenter.default.removeObserver(observer)
            scrollObserver = nil
        }
    }

    /// Update the scroll progress value
    private func updateScrollProgress() {
        guard let scrollView = scrollView,
              let docView = scrollView.documentView else {
            scrollProgress = 0
            return
        }

        let clipView = scrollView.contentView
        let contentHeight = docView.frame.height
        let viewHeight = clipView.bounds.height
        let currentY = clipView.bounds.origin.y

        // Calculate scrollable range
        let scrollableHeight = contentHeight - viewHeight

        if scrollableHeight <= 0 {
            // Content fits in view, consider it 100% read
            scrollProgress = 1
        } else {
            scrollProgress = min(1, max(0, currentY / scrollableHeight))
        }
    }

    deinit {
        if let observer = scrollObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

/// Helper to find and store reference to NSScrollView for page up/down functionality
struct ScrollViewAccessor: NSViewRepresentable {
    let scrollState: ArticleScrollState

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            findScrollView(in: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            findScrollView(in: nsView)
        }
    }

    private func findScrollView(in view: NSView) {
        var current: NSView? = view
        while let v = current {
            if let scrollView = v as? NSScrollView {
                scrollState.scrollView = scrollView
                return
            }
            current = v.superview
        }
    }
}

/// Right pane: full article detail with summary
struct ArticleDetailView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var scrollState: ArticleScrollState
    @State private var isSummarizing: Bool = false
    @State private var isFetchingContent: Bool = false
    @State private var isFetchingAuthenticated: Bool = false
    @State private var contentFetchError: String?
    @State private var contentHeight: CGFloat = 0
    @State private var summarizationError: String?
    @State private var summarizationElapsed: Int = 0
    @State private var summarizationTimer: Timer?
    @State private var showingLoginSheet: Bool = false
    @State private var loginURL: URL?
    @State private var loginSiteTitle: String = ""

    var body: some View {
        Group {
            if let article = appState.selectedArticleDetail {
                articleContentView(article: article)
            } else {
                ContentUnavailableView(
                    "Select an Article",
                    systemImage: "doc.text",
                    description: Text("Choose an article from the list to read its summary.")
                )
            }
        }
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: $showingLoginSheet) {
            if let url = loginURL {
                SiteLoginView(
                    initialURL: url,
                    siteTitle: loginSiteTitle,
                    onComplete: {
                        // After login, try fetching again if we have an article
                        if let article = appState.selectedArticleDetail {
                            fetchContentAuthenticated(article: article)
                        }
                    }
                )
            }
        }
    }

    // MARK: - Article Content View

    /// Maximum content width for reader mode (optimal reading width)
    private var readerModeMaxWidth: CGFloat { 720 }

    @ViewBuilder
    private func articleContentView(article: ArticleDetail) -> some View {
        VStack(spacing: 0) {
            // Reading progress bar
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * scrollState.scrollProgress)
                    .animation(.easeOut(duration: 0.1), value: scrollState.scrollProgress)
            }
            .frame(height: 3)
            .background(Color.accentColor.opacity(0.15))

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // Invisible anchor at the top for scroll-to-top functionality
                        Color.clear
                            .frame(height: 0)
                            .id(ArticleScrollState.topAnchorID)

                        articleBody(article: article)
                            .padding()
                            .frame(maxWidth: appState.readerModeEnabled ? readerModeMaxWidth : .infinity)
                    }
                    .frame(maxWidth: .infinity) // Centers content when width is constrained
                    .background(ScrollViewAccessor(scrollState: scrollState))
                }
                .onAppear {
                    scrollState.scrollProxy = proxy
                    // Start observing after a brief delay to ensure scrollView is set
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollState.startObservingScroll()
                    }
                }
                .onDisappear {
                    scrollState.stopObservingScroll()
                }
                .onChange(of: article.id) { _, _ in
                    scrollState.scrollToTop()
                }
            }
        }
    }

    // MARK: - Article Body

    @ViewBuilder
    private func articleBody(article: ArticleDetail) -> some View {
        // Use reader mode settings when in reader mode
        let fontSize = appState.readerModeEnabled
            ? appState.settings.readerModeFontSize
            : appState.settings.articleFontSize
        let lineSpacing = appState.readerModeEnabled
            ? appState.settings.readerModeLineSpacing
            : appState.settings.articleLineSpacing
        let appTypeface = appState.settings.appTypeface
        let contentTypeface = appState.settings.contentTypeface

        VStack(alignment: .leading, spacing: 16) {
            // Header
            articleHeader(article: article, fontSize: fontSize, lineSpacing: lineSpacing, appTypeface: appTypeface)

            Divider()

            // AI Summary section
            summarySection(article: article, fontSize: fontSize, lineSpacing: lineSpacing, appTypeface: appTypeface)

            // Key Points
            keyPointsSection(article: article, fontSize: fontSize, lineSpacing: lineSpacing, appTypeface: appTypeface)

            Divider()

            // Actions
            actionsSection(article: article)

            // Original content
            contentSection(article: article, fontSize: fontSize, lineSpacing: lineSpacing, appTypeface: appTypeface, contentTypeface: contentTypeface)
        }
    }


    // MARK: - Header Section

    @ViewBuilder
    private func articleHeader(article: ArticleDetail, fontSize: ArticleFontSize, lineSpacing: ArticleLineSpacing, appTypeface: AppTypeface) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Feed name pill
            if let feedName = feedName(for: article.feedId) {
                Text(feedName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor))
            }

            Text(article.title)
                .font(appTypeface.font(size: fontSize.titleFontSize + 4, weight: .bold))
                .lineSpacing(fontSize.titleFontSize * (lineSpacing.multiplier - 1))
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                Text(article.timeAgo)
                    .foregroundStyle(.secondary)

                if let readTime = article.estimatedReadTime {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Image(systemName: "book")
                        .foregroundStyle(.secondary)
                    Text(readTime)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if article.isBookmarked {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }
            }
            .font(.subheadline)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.15),
                    Color.accentColor.opacity(0.05),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Summary Section

    @ViewBuilder
    private func summarySection(article: ArticleDetail, fontSize: ArticleFontSize, lineSpacing: ArticleLineSpacing, appTypeface: AppTypeface) -> some View {
        if let summary = article.summaryFull {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("AI Summary", systemImage: "sparkles")
                        .font(appTypeface.font(size: fontSize.bodyFontSize + 2, weight: .semibold))
                        .foregroundStyle(.blue)

                    Spacer()

                    Button {
                        copySummaryToClipboard(article: article, summary: summary)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy summary, source, and URL")
                }

                Text(summary)
                    .font(appTypeface.font(size: fontSize.bodyFontSize))
                    .lineSpacing(fontSize.bodyFontSize * (lineSpacing.multiplier - 1))
                    .textSelection(.enabled)

                // Source info
                VStack(alignment: .leading, spacing: 4) {
                    if let feedName = feedName(for: article.feedId) {
                        Text(feedName)
                            .font(appTypeface.font(size: fontSize.bodyFontSize - 1))
                            .foregroundStyle(.secondary)
                    }

                    Link(article.originalUrl.absoluteString, destination: article.originalUrl)
                        .font(appTypeface.font(size: fontSize.bodyFontSize - 1))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.top, 4)
            }
            .padding()
            .background(Color.blue.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            generateSummaryView(article: article, fontSize: fontSize, lineSpacing: lineSpacing, appTypeface: appTypeface)
        }
    }

    private func copySummaryToClipboard(article: ArticleDetail, summary: String) {
        var text = summary + "\n\n"
        if let feedName = feedName(for: article.feedId) {
            text += "\(feedName)\n"
        }
        text += article.originalUrl.absoluteString

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @ViewBuilder
    private func generateSummaryView(article: ArticleDetail, fontSize: ArticleFontSize, lineSpacing: ArticleLineSpacing, appTypeface: AppTypeface) -> some View {
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

    // MARK: - Key Points Section

    @ViewBuilder
    private func keyPointsSection(article: ArticleDetail, fontSize: ArticleFontSize, lineSpacing: ArticleLineSpacing, appTypeface: AppTypeface) -> some View {
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
    }

    // MARK: - Actions Section

    @ViewBuilder
    private func actionsSection(article: ArticleDetail) -> some View {
        HStack(spacing: 12) {
            // Fetch Full Article button with menu for authenticated fetch
            if isFetchingContent || isFetchingAuthenticated {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(isFetchingAuthenticated ? "Loading with app session..." : "Fetching...")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial)
                .cornerRadius(6)
                .help(isFetchingAuthenticated ? "Loading page with your app session. This may take a few seconds to load all content." : "Fetching article content")
            } else {
                Menu {
                    Button {
                        fetchContent(articleId: article.id)
                    } label: {
                        Label("Standard Fetch", systemImage: "arrow.down.doc")
                    }

                    Divider()

                    Button {
                        fetchContentAuthenticated(article: article)
                    } label: {
                        Label("Fetch with App Session", systemImage: "key.fill")
                    }

                    Button {
                        showLoginSheet(for: article)
                    } label: {
                        Label("Log in to Site...", systemImage: "person.badge.key.fill")
                    }
                } label: {
                    Label("Fetch Full Article", systemImage: "arrow.down.doc")
                } primaryAction: {
                    fetchContent(articleId: article.id)
                }
                .buttonStyle(.borderedProminent)
                .fixedSize()
                .help("For paywalled sites: first use 'Log in to Site' to authenticate, then use 'Fetch with App Session'")
            }

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
            .buttonStyle(.borderedProminent)

            Button {
                NSWorkspace.shared.open(article.originalUrl)
            } label: {
                Label("Read Original", systemImage: "safari")
            }
            .buttonStyle(.borderedProminent)

            Spacer()

            // Share menu with options
            Menu {
                // Share URL only
                ShareLink(item: article.originalUrl) {
                    Label("Share Link", systemImage: "link")
                }

                // Share with summary (if available)
                if let summary = article.summaryShort ?? article.summaryFull, !summary.isEmpty {
                    ShareLink(item: shareTextWithSummary(article: article, summary: summary)) {
                        Label("Share with Summary", systemImage: "text.quote")
                    }

                    Divider()

                    Button {
                        copySummaryToClipboard(article: article, summary: summary)
                    } label: {
                        Label("Copy Summary", systemImage: "doc.on.doc")
                    }
                }

                Divider()

                Button {
                    copyLinkToClipboard(article: article)
                } label: {
                    Label("Copy Link", systemImage: "link")
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .fixedSize()
        }
    }

    private func shareTextWithSummary(article: ArticleDetail, summary: String) -> String {
        var text = article.title + "\n\n"
        text += summary + "\n\n"
        if let feedName = feedName(for: article.feedId) {
            text += "via \(feedName)\n"
        }
        text += article.originalUrl.absoluteString
        return text
    }

    private func copyLinkToClipboard(article: ArticleDetail) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(article.originalUrl.absoluteString, forType: .string)
    }

    // MARK: - Content Section

    @ViewBuilder
    private func contentSection(article: ArticleDetail, fontSize: ArticleFontSize, lineSpacing: ArticleLineSpacing, appTypeface: AppTypeface, contentTypeface: ContentTypeface) -> some View {
        if let content = article.content, !content.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Article Content")
                        .font(appTypeface.font(size: fontSize.bodyFontSize + 2, weight: .semibold))

                    Spacer()

                    // Content extraction controls
                    contentExtractionControls(article: article)
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
            noContentView(article: article)
        }
    }

    @ViewBuilder
    private func contentExtractionControls(article: ArticleDetail) -> some View {
        // Show error status if extraction failed (button is now in actions section)
        if let error = contentFetchError {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button {
                    fetchContent(articleId: article.id)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func noContentView(article: ArticleDetail) -> some View {
        VStack(spacing: 16) {
            if isFetchingContent {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.9)
                    Text("Extracting article content...")
                        .foregroundStyle(.secondary)
                    Text("This may take a few seconds")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else if let error = contentFetchError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)

                    Text("Failed to extract content")
                        .font(.headline)

                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Try Again") {
                        fetchContent(articleId: article.id)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)

                    Text("No content in feed")
                        .font(.headline)

                    Text("Extract the full article from the website")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        fetchContent(articleId: article.id)
                    } label: {
                        Label("Extract Article", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func fetchContent(articleId: Int) {
        contentFetchError = nil
        Task {
            isFetchingContent = true
            do {
                try await appState.fetchArticleContent(articleId: articleId)
            } catch {
                contentFetchError = error.localizedDescription
            }
            isFetchingContent = false
        }
    }

    private func fetchContentAuthenticated(article: ArticleDetail) {
        contentFetchError = nil
        Task {
            isFetchingAuthenticated = true
            do {
                // Use source URL for aggregators, otherwise use the article URL
                let fetchURL = article.sourceUrl ?? article.originalUrl
                try await appState.fetchArticleContentAuthenticated(articleId: article.id, url: fetchURL)
            } catch {
                contentFetchError = error.localizedDescription
            }
            isFetchingAuthenticated = false
        }
    }

    private func showLoginSheet(for article: ArticleDetail) {
        // Use source URL for aggregators, otherwise use the article URL
        let fetchURL = article.sourceUrl ?? article.originalUrl

        // Extract the base URL (scheme + host) for login
        if let host = fetchURL.host {
            loginURL = URL(string: "\(fetchURL.scheme ?? "https")://\(host)")
            loginSiteTitle = host.replacingOccurrences(of: "www.", with: "")
            showingLoginSheet = true
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
                    fetchContent(articleId: article.id)
                } label: {
                    if isFetchingContent {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 16, height: 16)
                    } else {
                        Label("Extract Article", systemImage: "arrow.down.doc")
                    }
                }
                .disabled(isFetchingContent)
                .help("Extract full article content from website")
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

            ToolbarItem {
                Button {
                    appState.readerModeEnabled.toggle()
                } label: {
                    Label(
                        appState.readerModeEnabled ? "Exit Reader Mode" : "Reader Mode",
                        systemImage: appState.readerModeEnabled ? "book.fill" : "book"
                    )
                }
                .help(appState.readerModeEnabled ? "Exit Reader Mode (f)" : "Enter Reader Mode (f)")
            }
        }
    }

    // MARK: - Helper Functions

    private func feedName(for feedId: Int) -> String? {
        appState.feeds.first { $0.id == feedId }?.name
    }

    private func startSummarization(articleId: Int) {
        summarizationError = nil
        summarizationElapsed = 0
        isSummarizing = true

        summarizationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            summarizationElapsed += 1
        }

        Task {
            do {
                try await appState.summarizeArticle(articleId: articleId)
                if appState.selectedArticleDetail?.id == articleId,
                   appState.selectedArticleDetail?.summaryFull == nil {
                    summarizationError = "Summary generation timed out. The server may be busy."
                }
            } catch {
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

#Preview {
    @Previewable @StateObject var scrollState = ArticleScrollState()
    ArticleDetailView(scrollState: scrollState)
        .environmentObject(AppState())
        .frame(width: 500, height: 600)
}
