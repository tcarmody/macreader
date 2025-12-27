import SwiftUI

/// Article content section with HTML rendering
struct ArticleContentSection: View {
    let article: ArticleDetail
    let fontSize: ArticleFontSize
    let lineSpacing: ArticleLineSpacing
    let appTypeface: AppTypeface
    let contentTypeface: ContentTypeface
    let theme: ArticleTheme

    @Binding var contentHeight: CGFloat

    let isFetchingContent: Bool
    let contentFetchError: String?
    let onFetchContent: () -> Void

    var body: some View {
        if let content = article.content, !content.isEmpty {
            contentView(content: content)
        } else {
            noContentView
        }
    }

    @ViewBuilder
    private func contentView(content: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Article Content")
                    .font(appTypeface.font(size: fontSize.bodyFontSize + 2, weight: .semibold))

                Spacer()

                // Content extraction controls
                contentExtractionControls
            }

            HTMLContentView(
                html: content,
                dynamicHeight: $contentHeight,
                fontSize: fontSize.bodyFontSize,
                lineHeight: lineSpacing.multiplier,
                fontFamily: contentTypeface.cssFontFamily,
                theme: theme
            )
            .frame(height: contentHeight)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var contentExtractionControls: some View {
        // Show error status if extraction failed
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
                    onFetchContent()
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
    private var noContentView: some View {
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
                        onFetchContent()
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
                        onFetchContent()
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
}
