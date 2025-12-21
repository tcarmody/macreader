import SwiftUI
import WebKit

/// Right pane: full library item detail with summary
struct LibraryItemDetailView: View {
    @EnvironmentObject var appState: AppState
    @State private var isSummarizing: Bool = false
    @State private var contentHeight: CGFloat = 200
    @State private var summarizationError: String?
    @State private var summarizationElapsed: Int = 0
    @State private var summarizationTimer: Timer?

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

    // MARK: - Content Section

    @ViewBuilder
    private func contentSection(item: LibraryItemDetail, fontSize: ArticleFontSize, lineSpacing: ArticleLineSpacing, contentTypeface: ContentTypeface) -> some View {
        if let content = item.content, !content.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Content")
                    .font(.headline)

                // For HTML content, use the web view; for plain text, use Text view
                if item.type == .url || item.type == .html {
                    HTMLContentView(
                        html: content,
                        dynamicHeight: $contentHeight,
                        fontSize: fontSize.bodyFontSize,
                        lineHeight: lineSpacing.multiplier,
                        fontFamily: contentTypeface.cssFontFamily
                    )
                    .frame(height: contentHeight)
                } else {
                    // Plain text content (PDF, DOCX, TXT, MD)
                    Text(content)
                        .font(appState.settings.appTypeface.font(size: fontSize.bodyFontSize))
                        .lineSpacing(fontSize.bodyFontSize * (lineSpacing.multiplier - 1))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
