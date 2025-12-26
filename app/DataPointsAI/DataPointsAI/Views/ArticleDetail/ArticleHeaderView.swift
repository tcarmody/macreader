import SwiftUI

/// Article header section with title, feed name, and metadata
struct ArticleHeaderView: View {
    let article: ArticleDetail
    let feedName: String?
    let fontSize: ArticleFontSize
    let lineSpacing: ArticleLineSpacing
    let appTypeface: AppTypeface

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Feed name pill
            if let feedName = feedName {
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
}
