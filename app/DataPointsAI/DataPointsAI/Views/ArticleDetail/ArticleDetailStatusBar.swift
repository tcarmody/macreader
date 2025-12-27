import SwiftUI

/// Status bar shown at the bottom of the article detail view
struct ArticleDetailStatusBar: View {
    let article: ArticleDetail
    let scrollProgress: Double

    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 16) {
            // Word count and read time
            if let wordCount = article.wordCount {
                StatItem(
                    icon: "text.word.spacing",
                    text: formatWordCount(wordCount)
                )
            }

            if let readTime = article.estimatedReadTime {
                StatItem(
                    icon: "clock",
                    text: readTime
                )
            }

            Divider()
                .frame(height: 12)

            // Summarization status
            summaryStatus

            Spacer()

            // Reading progress
            if scrollProgress > 0.01 {
                HStack(spacing: 4) {
                    Text("\(Int(scrollProgress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    ProgressView(value: scrollProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 50)
                        .tint(.accentColor)
                }
            }

            // Read status indicator
            readStatusIndicator
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Summary Status

    @ViewBuilder
    private var summaryStatus: some View {
        if article.summaryFull != nil {
            StatItem(
                icon: "sparkles",
                text: "Summarized",
                color: .purple
            )
        } else if article.summaryShort != nil {
            StatItem(
                icon: "sparkles",
                text: "Brief summary",
                color: .blue
            )
        } else {
            StatItem(
                icon: "sparkles.rectangle.stack",
                text: "Not summarized",
                color: .secondary
            )
        }
    }

    // MARK: - Read Status

    @ViewBuilder
    private var readStatusIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(article.isRead ? Color.secondary.opacity(0.3) : Color.blue)
                .frame(width: 6, height: 6)

            Text(article.isRead ? "Read" : "Unread")
                .font(.caption)
                .foregroundStyle(article.isRead ? Color.secondary : Color.blue)
        }
    }

    // MARK: - Helpers

    private func formatWordCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk words", Double(count) / 1000.0)
        }
        return "\(count) words"
    }
}

// MARK: - Stat Item Component

private struct StatItem: View {
    let icon: String
    let text: String
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)

            Text(text)
                .font(.caption)
                .foregroundStyle(color)
        }
    }
}

#Preview {
    VStack {
        Spacer()
        ArticleDetailStatusBar(
            article: ArticleDetail(
                id: 1,
                feedId: 1,
                url: URL(string: "https://example.com")!,
                sourceUrl: nil,
                title: "Sample Article",
                content: "Sample article content with enough words to calculate reading time.",
                summaryShort: "A short summary",
                summaryFull: "A full summary with more details",
                keyPoints: ["Point 1", "Point 2"],
                isRead: false,
                isBookmarked: false,
                publishedAt: Date(),
                createdAt: Date(),
                author: nil,
                readingTimeMinutes: 5,
                wordCountValue: 1250,
                featuredImage: nil,
                hasCodeBlocks: false,
                siteName: nil
            ),
            scrollProgress: 0.45
        )
        .environmentObject(AppState())
    }
}
