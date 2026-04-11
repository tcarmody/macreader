import SwiftUI
import WebKit

enum DetailTab: String, CaseIterable {
    case article = "Article"
    case ai = "AI Summary"
    case related = "Related"
    case chat = "Chat"
}

/// Right pane: full article detail with summary
struct ArticleDetailView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var scrollState: ArticleScrollState
    @State private var activeTab: DetailTab = .article
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
    @State private var hasChatHistory: Bool = false

    var body: some View {
        Group {
            if let article = appState.selectedArticleDetail {
                articleContentView(article: article)
                    .id(article.id)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity
                    ))
            } else {
                ContentUnavailableView(
                    "Select an Article",
                    systemImage: "doc.text",
                    description: Text("Choose an article from the list to read its summary.")
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.selectedArticleDetail?.id)
        .onChange(of: appState.selectedArticleDetail?.id) { _, _ in
            // Reset state when article changes
            contentHeight = 0
            activeTab = .article
            hasChatHistory = false
        }
        .onChange(of: appState.selectedArticleDetail?.relatedLinks?.count) { _, newCount in
            // Auto-switch to Related tab when links arrive, if user is still on Article tab
            if let count = newCount, count > 0, activeTab == .article {
                withAnimation(.easeInOut(duration: 0.15)) { activeTab = .related }
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

            // Tab strip (sticky, outside scroll view)
            detailTabStrip(article: article)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // Invisible anchor at the top for scroll-to-top functionality
                        Color.clear
                            .frame(height: 0)
                            .id(ArticleScrollState.topAnchorID)

                        tabContent(article: article)
                            .padding()
                            .frame(maxWidth: appState.readerModeEnabled ? readerModeMaxWidth : .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .background(ScrollViewAccessor(scrollState: scrollState))
                }
                .onAppear {
                    scrollState.scrollProxy = proxy
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
                .onChange(of: activeTab) { _, _ in
                    scrollState.scrollToTop()
                }
                .overlay(alignment: .bottomTrailing) {
                    // "Jump to AI Summary" chip — shown after scrolling 30%+ in the Article tab
                    let hasSummary = article.summaryFull != nil || article.summaryShort != nil
                    if hasSummary && activeTab == .article && scrollState.scrollProgress >= 0.3 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { activeTab = .ai }
                        } label: {
                            Label("AI Summary", systemImage: "sparkles")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.purple)
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }

            // Status bar at bottom
            ArticleDetailStatusBar(
                article: article,
                scrollProgress: scrollState.scrollProgress
            )
        }
    }

    // MARK: - Tab Strip

    @ViewBuilder
    private func detailTabStrip(article: ArticleDetail) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    detailTabButton(tab: tab, article: article)
                }
                Spacer()
            }
            .background(Color(NSColor.windowBackgroundColor))

            Divider()
        }
    }

    @ViewBuilder
    private func detailTabButton(tab: DetailTab, article: ArticleDetail) -> some View {
        let isActive = activeTab == tab
        let isDisabled = tab == .chat && article.summaryFull == nil
        let hasSummary = article.summaryFull != nil
        let hasRelated = article.relatedLinks?.isEmpty == false

        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if tab == .ai && !hasSummary && !isSummarizing {
                    startSummarization(articleId: article.id)
                } else if tab == .related && !hasRelated && !appState.isLoadingRelated {
                    Task { await appState.loadRelatedLinks(for: article.id) }
                }
                activeTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                // Status indicator
                if tab == .ai && isSummarizing {
                    ProgressView().scaleEffect(0.45).frame(width: 8, height: 8)
                } else if tab == .related && appState.isLoadingRelated {
                    ProgressView().scaleEffect(0.45).frame(width: 8, height: 8)
                } else if tab == .ai && hasSummary {
                    Circle().fill(Color.purple).frame(width: 6, height: 6)
                } else if tab == .related && hasRelated {
                    Circle().fill(Color.blue).frame(width: 6, height: 6)
                } else if tab == .chat && hasChatHistory {
                    Circle().fill(Color.blue).frame(width: 6, height: 6)
                } else if (tab == .ai || tab == .related) && !isDisabled {
                    Image(systemName: "plus")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.5))
                }

                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))

                // Count for Related tab
                if tab == .related, let count = article.relatedLinks?.count, count > 0 {
                    Text("(\(count))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(isActive ? Color.primary : Color.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .overlay(
                Rectangle()
                    .fill(isActive ? Color.accentColor : Color.clear)
                    .frame(height: 2),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(article: ArticleDetail) -> some View {
        let fontSize = appState.readerModeEnabled
            ? appState.settings.readerModeFontSize
            : appState.settings.articleFontSize
        let lineSpacing = appState.readerModeEnabled
            ? appState.settings.readerModeLineSpacing
            : appState.settings.articleLineSpacing
        let appTypeface = appState.settings.appTypeface
        let contentTypeface = appState.settings.contentTypeface

        switch activeTab {
        case .article:
            VStack(alignment: .leading, spacing: 16) {
                articleHeader(article: article, fontSize: fontSize, lineSpacing: lineSpacing, appTypeface: appTypeface)
                Divider()
                articleToolbar(article: article)
                Divider().padding(.vertical, 8)
                actionsSection(article: article)
                contentSection(article: article, fontSize: fontSize, lineSpacing: lineSpacing, appTypeface: appTypeface, contentTypeface: contentTypeface)
            }

        case .ai:
            VStack(alignment: .leading, spacing: 16) {
                summarySection(article: article, fontSize: fontSize, lineSpacing: lineSpacing, appTypeface: appTypeface)
                keyPointsSection(article: article, fontSize: fontSize, lineSpacing: lineSpacing, appTypeface: appTypeface)
            }

        case .related:
            ArticleRelatedLinksSection(
                relatedLinks: article.relatedLinks ?? [],
                fontSize: fontSize,
                lineSpacing: lineSpacing,
                appTypeface: appTypeface,
                isLoadingRelated: appState.isLoadingRelated,
                relatedLinksError: article.relatedLinksError,
                onFindRelated: {
                    Task { await appState.loadRelatedLinks(for: article.id) }
                }
            )

        case .chat:
            if article.summaryFull != nil {
                ArticleChatSection(
                    article: article,
                    fontSize: fontSize,
                    lineSpacing: lineSpacing,
                    appTypeface: appTypeface,
                    isExpanded: .constant(true),
                    hasChat: $hasChatHistory
                )
            }
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

            Text(article.displayTitle)
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

    // MARK: - Toolbar Section

    @ViewBuilder
    private func articleToolbar(article: ArticleDetail) -> some View {
        HStack(spacing: 16) {
            // Read toggle
            Button {
                Task {
                    try? await appState.markRead(articleId: article.id, isRead: !article.isRead)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: article.isRead ? "checkmark" : "circle")
                        .font(.system(size: 14))
                    Text("Read")
                        .font(.system(size: 13))
                }
                .foregroundColor(article.isRead ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help(article.isRead ? "Mark as unread" : "Mark as read")

            // Save/Bookmark toggle
            Button {
                Task {
                    try? await appState.toggleBookmark(articleId: article.id)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: article.isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 14))
                    Text("Save")
                        .font(.system(size: 13))
                }
                .foregroundColor(article.isBookmarked ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help(article.isBookmarked ? "Remove from saved" : "Save article")

            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 1, height: 20)

            Spacer()

            // Share button
            Menu {
                ShareLink(item: article.originalUrl) {
                    Label("Share Link", systemImage: "link")
                }

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
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Share article")

            // Open in browser button
            Button {
                NSWorkspace.shared.open(article.originalUrl)
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open in browser")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
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

            Button {
                Task {
                    await appState.loadRelatedLinks(for: article.id)
                }
            } label: {
                Label("Find Related", systemImage: "link.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isLoadingRelated)
            .help("Find related articles using neural search")

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
                    fontFamily: contentTypeface.cssFontFamily,
                    theme: appState.settings.articleTheme
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
                } else if activeTab == .article {
                    withAnimation(.easeInOut(duration: 0.15)) { activeTab = .ai }
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
