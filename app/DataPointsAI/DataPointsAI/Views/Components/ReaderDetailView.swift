import SwiftUI

/// Shared reader; origin changes capabilities, never the reading layout.
struct ReaderDetailView: View {
    let item: ReaderItem
    @ObservedObject var scrollState: ArticleScrollState
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var activeTab: DetailTab = .article
    @State private var contentHeight: CGFloat = 200
    @State private var isSummarizing = false
    @State private var isFetching = false
    @State private var isPromoting = false
    @State private var isFindingRelated = false
    @State private var operationError: String?
    @State private var hasChat = false
    @State private var showLogin = false
    @State private var showDelete = false
    @State private var summaryTask: Task<Void, Never>?
    @State private var scrollOffsets: [DetailTab: CGFloat] = [:]

    private var fontSize: ArticleFontSize {
        appState.readerModeEnabled ? appState.settings.readerModeFontSize : appState.settings.articleFontSize
    }
    private var lineSpacing: ArticleLineSpacing {
        appState.readerModeEnabled ? appState.settings.readerModeLineSpacing : appState.settings.articleLineSpacing
    }
    private var theme: ArticleTheme { appState.settings.articleTheme }
    private var contentLength: Int { item.content?.utf8.count ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Reader section", selection: $activeTab) {
                ForEach(DetailTab.allCases, id: \.self) { tab in Text(tab.rawValue).tag(tab) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .accessibilityLabel("Reader sections")
            .accessibilityHint("Choose Article, Summary, Related, or Chat")
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Color.clear.frame(height: 0).id(ArticleScrollState.topAnchorID)
                        ReaderHeader(item: item, fontSize: fontSize)
                        if let operationError {
                            Label(operationError, systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .textSelection(.enabled)
                                .foregroundStyle(.red)
                                .accessibilityAddTraits(.isStaticText)
                        }
                        tabContent
                        if showsActionFooter { actionFooter }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .background(ScrollViewAccessor(scrollState: scrollState))
                }
                .background(theme.backgroundColor)
                .foregroundStyle(theme.textColor)
                .tint(theme.accentColor)
                .environment(\.colorScheme, theme.preferredColorScheme ?? colorScheme)
                .onAppear { scrollState.scrollProxy = proxy }
            }
            statusBar
        }
        // Fully customizable, not `.reorderable`: the pinnable action items
        // below are hidden by default and only reachable if the user can add
        // them in View ▸ Customize Toolbar. Removing an item is safe now that
        // the Reader menu carries every action with a chord.
        //
        // Shares the window's one toolbar identity — see ToolbarIdentity.swift.
        .toolbar(id: mainWindowToolbarID) { readerToolbar }
        .toolbarRole(.editor)
        .onChange(of: activeTab) { oldTab, newTab in
            scrollOffsets[oldTab] = scrollState.offset
            ReaderPositionStore.shared.save(itemID: item.id, contentLength: contentLength,
                                            tab: newTab, offsets: scrollOffsets)
            scrollState.restoreOffset(scrollOffsets[newTab] ?? 0)
            announce("Showing \(newTab.rawValue)")
        }
        .onChange(of: contentHeight) { _, _ in
            if activeTab == .article { scrollState.finishRestoringOffset() }
        }
        .onChange(of: appState.pendingDetailTab) { _, _ in consumePendingTab() }
        .onChange(of: appState.pendingReaderCommand) { _, command in
            guard let command else { return }
            appState.pendingReaderCommand = nil
            perform(command)
        }
        .onAppear {
            if let saved = ReaderPositionStore.shared.restore(itemID: item.id, contentLength: contentLength) {
                activeTab = saved.0
                scrollOffsets = saved.1
                scrollState.restoreOffset(scrollOffsets[activeTab] ?? 0)
            }
            consumePendingTab()
        }
        .onDisappear {
            scrollOffsets[activeTab] = scrollState.offset
            ReaderPositionStore.shared.save(itemID: item.id, contentLength: contentLength,
                                            tab: activeTab, offsets: scrollOffsets)
            summaryTask?.cancel()
            scrollState.stopObservingScroll()
        }
        .sheet(isPresented: $showLogin) {
            if let url = item.url {
                SiteLoginView(initialURL: url, siteTitle: item.source) { fetchContent(authenticated: true) }
            }
        }
        .alert("Delete from Library?", isPresented: $showDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    do { try await appState.deleteLibraryItem(itemId: item.itemID) }
                    catch { appState.error = error.localizedDescription }
                }
            }
        } message: { Text("This deletes “\(item.title)” and its saved content.") }
    }

    @ViewBuilder private var tabContent: some View {
        switch activeTab {
        case .article:
            if let content = item.content, !content.isEmpty {
                HTMLContentView(html: item.renderedContent, dynamicHeight: $contentHeight,
                    fontSize: fontSize.bodyFontSize, lineHeight: lineSpacing.multiplier,
                    fontFamily: appState.settings.contentTypeface.cssFontFamily, theme: theme,
                    accessibilityContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
                    reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
                    .frame(height: contentHeight)
            } else {
                ContentUnavailableView {
                    Label("No Content Available", systemImage: "doc.text")
                } description: {
                    Text(item.origin == .feed ? "Extract the article to read it here." : "This item has no extracted text.")
                } actions: {
                    // Paywalled sites are exactly where plain extraction
                    // fails, so offer the session-backed paths here rather
                    // than making the user find them in a toolbar menu.
                    if item.origin == .feed {
                        actionButton(.extractArticle, showsIcon: false)
                        actionButton(.extractWithSession, showsIcon: false)
                        actionButton(.logInToSite, showsIcon: false)
                    }
                }
            }
        case .ai:
            ReaderSummarySection(item: item, fontSize: fontSize, lineSpacing: lineSpacing,
                                 isSummarizing: isSummarizing, onGenerate: summarize)
        case .related:
            ArticleRelatedLinksSection(relatedLinks: item.relatedLinks, fontSize: fontSize,
                lineSpacing: lineSpacing, appTypeface: appState.settings.appTypeface,
                isLoadingRelated: isFindingRelated, relatedLinksError: item.relatedLinksError,
                onFindRelated: findRelated)
        case .chat:
            if item.summaryFull != nil {
                ArticleChatSection(articleId: item.itemID, headerLabel: "Chat", fontSize: fontSize,
                    lineSpacing: lineSpacing, appTypeface: appState.settings.appTypeface,
                    isExpanded: .constant(true), hasChat: $hasChat)
            } else {
                ContentUnavailableView {
                    Label("Start with a Summary", systemImage: "bubble.left.and.bubble.right")
                } description: { Text("Generate a summary to discuss this item.") }
                actions: { Button("Generate Summary") { summarize() }.disabled(isSummarizing) }
            }
        }
    }

    /// Only under the article itself, and only when there's something to have
    /// read — the empty state already offers the extraction actions inline,
    /// and repeating them under a "No Content Available" placeholder would
    /// just be the same three buttons twice.
    private var showsActionFooter: Bool {
        activeTab == .article && !(item.content?.isEmpty ?? true)
    }

    /// End-of-article actions. These are also in the toolbar and the Reader
    /// menu; this surface exists because finishing the article is when most
    /// of them actually get used, and the cursor is already down here.
    ///
    /// Deliberately *not* a floating control strip — it sits after the text,
    /// scrolls with it, and is separated by a rule, so it reads as the end of
    /// the document rather than the in-content button bar MACUX.md rules out.
    private var actionFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("Actions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 8, alignment: .leading)],
                      alignment: .leading, spacing: 8) {
                ForEach(ReaderAction.sections(for: item).flatMap { $0 }) { action in
                    Button(action.title(for: item), systemImage: action.systemImage,
                           role: action.role) { perform(action.command) }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(!action.isEnabled(for: item, activity: activity))
                }
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Article actions")
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if isSummarizing || isFetching || isPromoting || isFindingRelated {
                ProgressView().controlSize(.small)
                Text(isSummarizing ? "Generating summary…" : isFetching ? "Extracting content…" : isPromoting ? "Sending to Composer…" : "Finding related articles…")
            } else {
                if let readTime = item.readTime { Text(readTime) }
                if item.summaryFull != nil { Label("Summarized", systemImage: "sparkles") }
            }
            Spacer(minLength: 4)
            Text("\(Int(scrollState.scrollProgress * 100))%")
                .monospacedDigit()
                .accessibilityLabel("Reading progress, \(Int(scrollState.scrollProgress * 100)) percent")
            Text(item.isRead ? "Read" : "Unread")
        }
        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        .padding(.horizontal, 12).padding(.vertical, 6).background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusAccessibilityLabel)
    }

    private var statusAccessibilityLabel: String {
        let progress = Int(scrollState.scrollProgress * 100)
        if isSummarizing { return "Generating summary. Reading progress, \(progress) percent." }
        if isFetching { return "Extracting content. Reading progress, \(progress) percent." }
        if isPromoting { return "Sending to Composer. Reading progress, \(progress) percent." }
        if isFindingRelated { return "Finding related articles. Reading progress, \(progress) percent." }
        let readState = item.isRead ? "Read" : "Unread"
        return "Reading progress, \(progress) percent. \(readState)."
    }

    @ToolbarContentBuilder private var readerToolbar: some CustomizableToolbarContent {
        ToolbarItem(id: "reader-mode", placement: .navigation, showsByDefault: true) {
            Button { appState.readerModeEnabled.toggle() } label: {
                Label("Reader Mode", systemImage: appState.readerModeEnabled ? "book.fill" : "book")
            }
            .helpLabel(appState.readerModeEnabled ? "Exit Reader Mode (f)" : "Enter Reader Mode (f)")
            .accessibilityHint(appState.readerModeEnabled ? "Uses the reader typography settings" : "Uses the reader typography settings")
        }
        ToolbarItem(id: "reader-mark-read", placement: .primaryAction, showsByDefault: true) {
            Button { updateRead() } label: {
                Label(item.isRead ? "Mark as Unread" : "Mark as Read", systemImage: item.isRead ? "envelope.badge" : "envelope.open")
            }.helpLabel(item.isRead ? "Mark as Unread" : "Mark as Read")
        }
        ToolbarItem(id: "reader-bookmark", placement: .primaryAction, showsByDefault: true) {
            Button { toggleBookmark() } label: {
                Label(item.isBookmarked ? "Remove Bookmark" : "Bookmark", systemImage: item.isBookmarked ? "bookmark.fill" : "bookmark")
            }.helpLabel(item.isBookmarked ? "Remove Bookmark" : "Bookmark")
        }
        ToolbarItem(id: "reader-share", placement: .primaryAction, showsByDefault: true) {
            Menu {
                if let url = item.url { ShareLink(item: url) { Label("Share Link", systemImage: "link") } }
                ShareLink(item: item.shareText) { Label("Share with Summary", systemImage: "text.quote") }
                    .disabled(item.summaryFull == nil && item.summaryShort == nil)
                Button("Copy Summary") {
                    copy([item.summaryFull ?? item.summaryShort, item.source, item.url?.absoluteString].compactMap { $0 }.joined(separator: "\n\n"))
                }.disabled(item.summaryFull == nil && item.summaryShort == nil)
                if let url = item.url { Button("Copy Link") { copy(url.absoluteString) } }
            } label: { Label("Share", systemImage: "square.and.arrow.up") }
                .helpLabel("Share")
        }
        ToolbarItem(id: "reader-more-actions", placement: .primaryAction, showsByDefault: true) {
            Menu {
                if let url = item.url {
                    Button("Open in Browser", systemImage: "safari") { NSWorkspace.shared.open(url) }
                }
                overflowActions
            } label: { Label("More Actions", systemImage: "ellipsis.circle") }
                .helpLabel("More Actions")
        }
        pinnableToolbarItems
    }

    /// Hidden by default so the row stays scannable (MACUX.md caps it at
    /// ~5–7), but available in View ▸ Customize Toolbar for anyone who runs
    /// one of these on every article.
    ///
    /// Listed explicitly because `ForEach` isn't `CustomizableToolbarContent`
    /// — SwiftUI resolves it as a `ViewBuilder`. `ReaderAction.isPinnable`
    /// stays the source of truth and `ReaderInteractionTests` asserts this
    /// list matches it. Grouping them here also keeps `readerToolbar` at 6
    /// elements instead of 10, the point where the builder silently truncates.
    @ToolbarContentBuilder private var pinnableToolbarItems: some CustomizableToolbarContent {
        pinnableItem(.extractArticle)
        pinnableItem(.extractWithSession)
        pinnableItem(.summarize)
        pinnableItem(.findRelated)
        pinnableItem(.sendToComposer)
    }

    @ToolbarContentBuilder private func pinnableItem(_ action: ReaderAction) -> some CustomizableToolbarContent {
        ToolbarItem(id: action.toolbarID, placement: .primaryAction, showsByDefault: false) {
            Button { perform(action.command) } label: {
                Label(action.title(for: item), systemImage: action.systemImage)
            }
            .helpLabel(action.title(for: item))
            .disabled(!action.isEnabled(for: item, activity: activity))
        }
    }

    /// The overflow menu's action list, grouped into divider-separated runs.
    /// Unavailable actions are omitted here — extraction is meaningless for a
    /// local PDF — while the menu bar shows them disabled instead.
    @ViewBuilder private var overflowActions: some View {
        let sections = ReaderAction.sections(for: item)
        ForEach(Array(sections.enumerated()), id: \.offset) { index, actions in
            // Only divide from something that precedes it.
            if index > 0 || item.url != nil { Divider() }
            ForEach(actions) { actionButton($0) }
        }
    }

    @ViewBuilder private func actionButton(_ action: ReaderAction, showsIcon: Bool = true) -> some View {
        let title = action.title(for: item)
        let run = { perform(action.command) }
        Group {
            if showsIcon {
                Button(title, systemImage: action.systemImage, role: action.role, action: run)
            } else {
                Button(title, role: action.role, action: run)
            }
        }
        .disabled(!action.isEnabled(for: item, activity: activity))
    }

    private var activity: ReaderActivity {
        ReaderActivity(isFetching: isFetching, isSummarizing: isSummarizing,
                       isFindingRelated: isFindingRelated, isPromoting: isPromoting)
    }

    private func perform(_ command: ReaderCommand) {
        switch command {
        case .extract: fetchContent()
        case .extractAuthenticated: fetchContent(authenticated: true)
        case .login: showLogin = true
        case .summarize: summarize()
        case .findRelated: activeTab = .related; findRelated()
        case .promote: promote()
        case .delete: showDelete = true
        }
    }

    private func consumePendingTab() {
        guard let tab = appState.pendingDetailTab else { return }
        appState.pendingDetailTab = nil
        activeTab = tab
        if tab == .ai && item.summaryFull == nil { summarize() }
        if tab == .related && item.relatedLinks.isEmpty { findRelated() }
    }

    private func announce(_ message: String) {
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: 90
        ])
    }
    private func updateRead() {
        Task {
            do {
                if item.origin == .library { try await appState.markLibraryItemRead(itemId: item.itemID, isRead: !item.isRead) }
                else { try await appState.markRead(articleId: item.itemID, isRead: !item.isRead) }
            } catch { appState.error = error.localizedDescription }
        }
    }
    private func toggleBookmark() {
        Task {
            do {
                if item.origin == .library { try await appState.toggleLibraryItemBookmark(itemId: item.itemID) }
                else { try await appState.toggleBookmark(articleId: item.itemID) }
            } catch { appState.error = error.localizedDescription }
        }
    }
    private func summarize() {
        guard !isSummarizing else { return }
        activeTab = .ai
        isSummarizing = true
        operationError = nil
        summaryTask = Task {
            defer { isSummarizing = false }
            do {
                if item.origin == .library { try await appState.summarizeLibraryItem(itemId: item.itemID) }
                else { try await appState.summarizeArticle(articleId: item.itemID) }
            } catch { if !error.isCancellation { operationError = error.localizedDescription } }
        }
    }
    private func findRelated() {
        guard !isFindingRelated else { return }
        isFindingRelated = true
        Task {
            defer { isFindingRelated = false }
            if item.origin == .library { await appState.loadRelatedLinksForLibraryItem(itemId: item.itemID) }
            else { await appState.loadRelatedLinks(for: item.itemID) }
        }
    }
    private func fetchContent(authenticated: Bool = false) {
        guard !isFetching, let url = item.url, item.origin == .feed else { return }
        isFetching = true
        operationError = nil
        Task {
            defer { isFetching = false }
            do {
                if authenticated { try await appState.fetchArticleContentAuthenticated(articleId: item.itemID, url: url) }
                else { try await appState.fetchArticleContent(articleId: item.itemID) }
            } catch { operationError = error.localizedDescription }
        }
    }
    private func promote() {
        isPromoting = true
        operationError = nil
        Task {
            defer { isPromoting = false }
            do {
                if item.origin == .library { try await appState.promoteLibraryItemToComposer(itemId: item.itemID) }
                else { try await appState.promoteArticleToComposer(articleId: item.itemID) }
            } catch { operationError = error.localizedDescription }
        }
    }
    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct ReaderHeader: View {
    let item: ReaderItem
    let fontSize: ArticleFontSize
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(item.source, systemImage: item.sourceSymbol)
                .font(.subheadline).foregroundStyle(appState.settings.articleTheme.secondaryTextColor)
            Text(item.title)
                .font(appState.settings.appTypeface.font(size: fontSize.titleFontSize, weight: .bold))
                .textSelection(.enabled).accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { metadata }
                VStack(alignment: .leading, spacing: 4) { metadata }
            }
            .font(.caption).foregroundStyle(appState.settings.articleTheme.secondaryTextColor)
            if item.isFeatured, let note = item.featuredNote, !note.isEmpty {
                Text(note.autoLinked()).font(.callout).textSelection(.enabled)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private var metadata: some View {
        Text(item.date, format: .dateTime.month(.abbreviated).day().year())
        if let readTime = item.readTime { Text(readTime) }
        if item.isFeatured { Label("Featured", systemImage: "star.fill") }
        if item.isBookmarked { Label("Bookmarked", systemImage: "bookmark.fill") }
    }
}

private struct ReaderSummarySection: View {
    let item: ReaderItem
    let fontSize: ArticleFontSize
    let lineSpacing: ArticleLineSpacing
    let isSummarizing: Bool
    let onGenerate: () -> Void
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if isSummarizing { ProgressView("Generating summary…") }
            if let summary = item.summaryFull ?? item.summaryShort {
                Text(summary.smartQuotes)
                    .font(appState.settings.appTypeface.font(size: fontSize.bodyFontSize))
                    .lineSpacing(fontSize.bodyFontSize * (lineSpacing.multiplier - 1))
                    .textSelection(.enabled)
            }
            if item.summaryFull == nil && !isSummarizing {
                Button("Generate Summary", systemImage: "sparkles", action: onGenerate).buttonStyle(.bordered)
            }
            if !item.keyPoints.isEmpty {
                ReaderKeyPointsSection(keyPoints: item.keyPoints, fontSize: fontSize,
                    lineSpacing: lineSpacing, appTypeface: appState.settings.appTypeface)
            }
            if let url = item.url { Link(item.source, destination: url).font(.callout) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReaderKeyPointsSection: View {
    let keyPoints: [String]
    let fontSize: ArticleFontSize
    let lineSpacing: ArticleLineSpacing
    let appTypeface: AppTypeface

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Key Points")
                .font(appTypeface.font(size: fontSize.bodyFontSize + 2, weight: .semibold))
            ForEach(keyPoints, id: \.self) { point in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill").font(.system(size: 5)).padding(.top, 7)
                    Text(point.smartQuotes)
                        .font(appTypeface.font(size: fontSize.bodyFontSize))
                        .lineSpacing(fontSize.bodyFontSize * (lineSpacing.multiplier - 1))
                        .textSelection(.enabled)
                }
            }
        }
    }
}
