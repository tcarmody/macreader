import SwiftUI
import WebKit
import AppKit

/// NSTextView wrapper for efficient rendering of large text content
struct LargeTextView: NSViewRepresentable {
    let text: String
    let font: NSFont
    let lineSpacing: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 8)

        // Configure text container
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Create paragraph style with line spacing
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.labelColor
        ]

        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
    }
}

/// Right pane: full library item detail with summary
struct LibraryItemDetailView: View {
    @EnvironmentObject var appState: AppState
    @State private var isSummarizing: Bool = false
    @State private var contentHeight: CGFloat = 200
    @State private var summarizationError: String?
    @State private var summarizationElapsed: Int = 0
    @State private var summarizationTimer: Timer?
    @State private var showFullContent: Bool = false

    var body: some View {
        Group {
            if let item = appState.selectedLibraryItemDetail {
                itemContentView(item: item)
            } else {
                ContentUnavailableView(
                    "Select an Item",
                    systemImage: "books.vertical",
                    description: Text("Choose an item from the library to view its content.")
                )
            }
        }
        .toolbar {
            toolbarContent
        }
    }

    // MARK: - Item Content View

    @ViewBuilder
    private func itemContentView(item: LibraryItemDetail) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                itemBody(item: item)
                    .padding()
            }
        }
        .onChange(of: item.id) { _, _ in
            // Reset content expansion state when viewing a new item
            showFullContent = false
        }
    }

    // MARK: - Item Body

    @ViewBuilder
    private func itemBody(item: LibraryItemDetail) -> some View {
        let fontSize = appState.settings.articleFontSize
        let lineSpacing = appState.settings.articleLineSpacing
        let appTypeface = appState.settings.appTypeface
        let contentTypeface = appState.settings.contentTypeface

        VStack(alignment: .leading, spacing: 16) {
            // Header
            itemHeader(item: item, fontSize: fontSize, appTypeface: appTypeface)

            Divider()

            // AI Summary section
            summarySection(item: item, fontSize: fontSize, lineSpacing: lineSpacing, appTypeface: appTypeface)

            // Key Points
            keyPointsSection(item: item, fontSize: fontSize, lineSpacing: lineSpacing, appTypeface: appTypeface)

            Divider()

            // Actions
            actionsSection(item: item)

            // Related links
            relatedLinksSection(item: item, fontSize: fontSize, lineSpacing: lineSpacing, appTypeface: appTypeface)

            // Original content
            contentSection(item: item, fontSize: fontSize, lineSpacing: lineSpacing, contentTypeface: contentTypeface)
        }
    }

    // MARK: - Header Section

    @ViewBuilder
    private func itemHeader(item: LibraryItemDetail, fontSize: ArticleFontSize, appTypeface: AppTypeface) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Type badge
            HStack {
                Label(item.type.label, systemImage: item.type.iconName)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .clipShape(Capsule())

                Spacer()
            }

            Text(item.displayName)
                .font(appTypeface.font(size: fontSize.titleFontSize, weight: .bold))
                .textSelection(.enabled)

            HStack(spacing: 8) {
                if let fileName = item.fileName {
                    Text(fileName)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                }

                Text(formatDate(item.createdAt))
                    .foregroundStyle(.secondary)

                Spacer()

                if item.isBookmarked {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }
            }
            .font(.subheadline)
        }
    }

    // MARK: - Summary Section

    @ViewBuilder
    private func summarySection(item: LibraryItemDetail, fontSize: ArticleFontSize, lineSpacing: ArticleLineSpacing, appTypeface: AppTypeface) -> some View {
        if let summary = item.summaryFull {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("AI Summary", systemImage: "sparkles")
                        .font(appTypeface.font(size: fontSize.bodyFontSize + 2, weight: .semibold))
                        .foregroundStyle(.blue)

                    Spacer()

                    Button {
                        copySummaryToClipboard(item: item, summary: summary)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy summary and source info")
                }

                Text(summary)
                    .font(appTypeface.font(size: fontSize.bodyFontSize))
                    .lineSpacing(fontSize.bodyFontSize * (lineSpacing.multiplier - 1))
                    .textSelection(.enabled)

                // Source info
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.type.label)
                        .font(appTypeface.font(size: fontSize.bodyFontSize - 1))
                        .foregroundStyle(.secondary)

                    if item.type == .url {
                        Link(item.url.absoluteString, destination: item.url)
                            .font(appTypeface.font(size: fontSize.bodyFontSize - 1))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else if let fileName = item.fileName {
                        Text(fileName)
                            .font(appTypeface.font(size: fontSize.bodyFontSize - 1))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
            .padding()
            .background(Color.blue.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            generateSummaryView(item: item, fontSize: fontSize, lineSpacing: lineSpacing, appTypeface: appTypeface)
        }
    }

    private func copySummaryToClipboard(item: LibraryItemDetail, summary: String) {
        var text = summary + "\n\n"
        text += "\(item.type.label)\n"
        if item.type == .url {
            text += item.url.absoluteString
        } else if let fileName = item.fileName {
            text += fileName
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @ViewBuilder
    private func generateSummaryView(item: LibraryItemDetail, fontSize: ArticleFontSize, lineSpacing: ArticleLineSpacing, appTypeface: AppTypeface) -> some View {
        VStack(spacing: 12) {
            if isSummarizing {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Generating summary... \(summarizationElapsed)s")
                    .foregroundStyle(.secondary)
                if summarizationElapsed > 10 {
                    Text("Complex documents may take up to 60 seconds")
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
                    startSummarization(itemId: item.id)
                }
                .buttonStyle(.bordered)
            } else {
                if let shortSummary = item.summaryShort {
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
                    startSummarization(itemId: item.id)
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
    private func keyPointsSection(item: LibraryItemDetail, fontSize: ArticleFontSize, lineSpacing: ArticleLineSpacing, appTypeface: AppTypeface) -> some View {
        if let keyPoints = item.keyPoints, !keyPoints.isEmpty {
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
    private func actionsSection(item: LibraryItemDetail) -> some View {
        HStack(spacing: 16) {
            // Open original (for URLs)
            if item.type == .url {
                Button {
                    NSWorkspace.shared.open(item.url)
                } label: {
                    Label("Open URL", systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                Task {
                    try? await appState.toggleLibraryItemBookmark(itemId: item.id)
                }
            } label: {
                Label(
                    item.isBookmarked ? "Saved" : "Save",
                    systemImage: item.isBookmarked ? "star.fill" : "star"
                )
            }
            .buttonStyle(.bordered)

            // Context/Related Links button
            Button {
                if item.relatedLinks == nil || (item.relatedLinks?.isEmpty ?? true) {
                    Task {
                        await appState.loadRelatedLinksForLibraryItem(itemId: item.id)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if appState.isLoadingRelated {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "link")
                            .foregroundColor((item.relatedLinks?.isEmpty == false) ? .blue : nil)
                    }
                    Text((item.relatedLinks?.isEmpty == false) ? "Contextualized" : "Context")
                }
            }
            .buttonStyle(.bordered)
            .disabled(appState.isLoadingRelated || (item.relatedLinks?.isEmpty == false))
            .help((item.relatedLinks?.isEmpty == false) ? "Related articles found" : "Find semantically related articles using neural search")

            Spacer()

            if item.type == .url {
                ShareLink(item: item.url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }

            Button(role: .destructive) {
                Task {
                    try? await appState.deleteLibraryItem(itemId: item.id)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Related Links Section

    @ViewBuilder
    private func relatedLinksSection(item: LibraryItemDetail, fontSize: ArticleFontSize, lineSpacing: ArticleLineSpacing, appTypeface: AppTypeface) -> some View {
        // Only show section when there are links, loading, or error (matching article behavior)
        if let relatedLinks = item.relatedLinks, !relatedLinks.isEmpty {
            ArticleRelatedLinksSection(
                relatedLinks: relatedLinks,
                fontSize: fontSize,
                lineSpacing: lineSpacing,
                appTypeface: appTypeface,
                isLoadingRelated: appState.isLoadingRelated,
                relatedLinksError: item.relatedLinksError,
                onFindRelated: {
                    Task {
                        await appState.loadRelatedLinksForLibraryItem(itemId: item.id)
                    }
                }
            )
        } else if appState.isLoadingRelated || item.relatedLinksError != nil {
            // Show loading/error state even if no links yet
            ArticleRelatedLinksSection(
                relatedLinks: [],
                fontSize: fontSize,
                lineSpacing: lineSpacing,
                appTypeface: appTypeface,
                isLoadingRelated: appState.isLoadingRelated,
                relatedLinksError: item.relatedLinksError,
                onFindRelated: {
                    Task {
                        await appState.loadRelatedLinksForLibraryItem(itemId: item.id)
                    }
                }
            )
        }
    }

    // MARK: - Content Section

    /// Character threshold for showing "Show More" button
    private let contentPreviewLimit = 5000

    @ViewBuilder
    private func contentSection(item: LibraryItemDetail, fontSize: ArticleFontSize, lineSpacing: ArticleLineSpacing, contentTypeface: ContentTypeface) -> some View {
        if let content = item.content, !content.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Content")
                        .font(.headline)

                    Spacer()

                    // Show character count for large documents
                    if content.count > contentPreviewLimit {
                        Text("\(content.count.formatted()) characters")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // For HTML content, use the web view; for plain text, use efficient text view
                if item.type == .url || item.type == .html {
                    HTMLContentView(
                        html: content,
                        dynamicHeight: $contentHeight,
                        fontSize: fontSize.bodyFontSize,
                        lineHeight: lineSpacing.multiplier,
                        fontFamily: contentTypeface.cssFontFamily,
                        theme: appState.settings.articleTheme
                    )
                    .frame(height: contentHeight)
                } else {
                    // Plain text content (PDF, DOCX, TXT, MD)
                    // Use NSTextView-based view for efficient rendering of large documents
                    let nsFont = NSFont.systemFont(ofSize: fontSize.bodyFontSize)
                    let extraLineSpacing = fontSize.bodyFontSize * (lineSpacing.multiplier - 1)

                    if content.count > contentPreviewLimit && !showFullContent {
                        // Show truncated preview for very large documents
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(content.prefix(contentPreviewLimit)) + "...")
                                .font(.system(size: fontSize.bodyFontSize))
                                .lineSpacing(extraLineSpacing)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                showFullContent = true
                            } label: {
                                Label("Show Full Content", systemImage: "chevron.down")
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        // Use efficient NSTextView for full content
                        LargeTextView(
                            text: content,
                            font: nsFont,
                            lineSpacing: extraLineSpacing
                        )
                        .frame(minHeight: 200, maxHeight: 600)

                        if content.count > contentPreviewLimit {
                            Button {
                                showFullContent = false
                            } label: {
                                Label("Collapse Content", systemImage: "chevron.up")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(.top, 8)
        } else {
            VStack(spacing: 12) {
                Text("No content available")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let item = appState.selectedLibraryItemDetail {
            ToolbarItem {
                Button {
                    Task {
                        let newStatus = !(appState.selectedLibraryItemDetail?.isRead ?? false)
                        try? await appState.markLibraryItemRead(itemId: item.id, isRead: newStatus)
                    }
                } label: {
                    Label(
                        item.isRead ? "Mark as Unread" : "Mark as Read",
                        systemImage: item.isRead ? "envelope.open" : "envelope.badge"
                    )
                }
                .help(item.isRead ? "Mark as Unread" : "Mark as Read")
            }

            ToolbarItem {
                Button {
                    Task {
                        try? await appState.toggleLibraryItemBookmark(itemId: item.id)
                    }
                } label: {
                    Label(
                        item.isBookmarked ? "Remove Bookmark" : "Bookmark",
                        systemImage: item.isBookmarked ? "star.fill" : "star"
                    )
                }
                .help(item.isBookmarked ? "Remove Bookmark" : "Bookmark")
            }

            ToolbarItem {
                Button {
                    startSummarization(itemId: item.id)
                } label: {
                    if isSummarizing {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 16, height: 16)
                    } else {
                        Label(
                            item.summaryFull != nil ? "Regenerate Summary" : "Generate Summary",
                            systemImage: item.summaryFull != nil ? "sparkles" : "sparkles.rectangle.stack"
                        )
                    }
                }
                .disabled(isSummarizing)
                .help(item.summaryFull != nil ? "Regenerate Summary" : "Generate Summary")
            }
        }
    }

    // MARK: - Helper Functions

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func startSummarization(itemId: Int) {
        summarizationError = nil
        summarizationElapsed = 0
        isSummarizing = true

        summarizationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            summarizationElapsed += 1
        }

        Task {
            do {
                try await appState.summarizeLibraryItem(itemId: itemId)
                if appState.selectedLibraryItemDetail?.id == itemId,
                   appState.selectedLibraryItemDetail?.summaryFull == nil {
                    summarizationError = "Summary generation timed out. The server may be busy."
                }
            } catch {
                if appState.selectedLibraryItemDetail?.id == itemId {
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
    LibraryItemDetailView()
        .environmentObject(AppState())
        .frame(width: 500, height: 600)
}
