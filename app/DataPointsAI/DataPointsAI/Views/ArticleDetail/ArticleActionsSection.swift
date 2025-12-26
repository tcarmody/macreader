import SwiftUI

/// Actions section with fetch, bookmark, and share buttons
struct ArticleActionsSection: View {
    @EnvironmentObject var appState: AppState
    let article: ArticleDetail
    let feedName: String?

    let isFetchingContent: Bool
    let isFetchingAuthenticated: Bool

    let onFetchContent: () -> Void
    let onFetchAuthenticated: () -> Void
    let onShowLogin: () -> Void

    var body: some View {
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
                        onFetchContent()
                    } label: {
                        Label("Standard Fetch", systemImage: "arrow.down.doc")
                    }

                    Divider()

                    Button {
                        onFetchAuthenticated()
                    } label: {
                        Label("Fetch with App Session", systemImage: "key.fill")
                    }

                    Button {
                        onShowLogin()
                    } label: {
                        Label("Log in to Site...", systemImage: "person.badge.key.fill")
                    }
                } label: {
                    Label("Fetch Full Article", systemImage: "arrow.down.doc")
                } primaryAction: {
                    onFetchContent()
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
            shareMenu
        }
    }

    @ViewBuilder
    private var shareMenu: some View {
        Menu {
            // Share URL only
            ShareLink(item: article.originalUrl) {
                Label("Share Link", systemImage: "link")
            }

            // Share with summary (if available)
            if let summary = article.summaryShort ?? article.summaryFull, !summary.isEmpty {
                ShareLink(item: shareTextWithSummary(summary: summary)) {
                    Label("Share with Summary", systemImage: "text.quote")
                }

                Divider()

                Button {
                    copySummaryToClipboard(summary: summary)
                } label: {
                    Label("Copy Summary", systemImage: "doc.on.doc")
                }
            }

            Divider()

            Button {
                copyLinkToClipboard()
            } label: {
                Label("Copy Link", systemImage: "link")
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.bordered)
        .fixedSize()
    }

    private func shareTextWithSummary(summary: String) -> String {
        var text = article.title + "\n\n"
        text += summary + "\n\n"
        if let feedName = feedName {
            text += "via \(feedName)\n"
        }
        text += article.originalUrl.absoluteString
        return text
    }

    private func copySummaryToClipboard(summary: String) {
        var text = summary + "\n\n"
        if let feedName = feedName {
            text += "\(feedName)\n"
        }
        text += article.originalUrl.absoluteString

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyLinkToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(article.originalUrl.absoluteString, forType: .string)
    }
}
