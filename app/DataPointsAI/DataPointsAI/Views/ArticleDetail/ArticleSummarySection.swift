import SwiftUI

/// AI summary section for articles
struct ArticleSummarySection: View {
    let article: ArticleDetail
    let feedName: String?
    let fontSize: ArticleFontSize
    let lineSpacing: ArticleLineSpacing
    let appTypeface: AppTypeface

    let isSummarizing: Bool
    let summarizationError: String?
    let summarizationElapsed: Int
    let onGenerateSummary: () -> Void

    var body: some View {
        if let summary = article.summaryFull {
            existingSummaryView(summary: summary)
        } else {
            generateSummaryView
        }
    }

    @ViewBuilder
    private func existingSummaryView(summary: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI Summary", systemImage: "sparkles")
                    .font(appTypeface.font(size: fontSize.bodyFontSize + 2, weight: .semibold))
                    .foregroundStyle(.blue)

                Spacer()

                Button {
                    copySummaryToClipboard(summary: summary)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Copy summary, source, and URL")
            }

            Text(summary.smartQuotes)
                .font(appTypeface.font(size: fontSize.bodyFontSize))
                .lineSpacing(fontSize.bodyFontSize * (lineSpacing.multiplier - 1))
                .textSelection(.enabled)

            // Source info
            VStack(alignment: .leading, spacing: 4) {
                if let feedName = feedName {
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
    }

    @ViewBuilder
    private var generateSummaryView: some View {
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
                    onGenerateSummary()
                }
                .buttonStyle(.bordered)
            } else {
                if let shortSummary = article.summaryShort {
                    Text(shortSummary.smartQuotes)
                        .font(appTypeface.font(size: fontSize.bodyFontSize))
                        .lineSpacing(fontSize.bodyFontSize * (lineSpacing.multiplier - 1))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No summary available")
                        .font(appTypeface.font(size: fontSize.bodyFontSize))
                        .foregroundStyle(.secondary)
                }

                Button("Generate Summary") {
                    onGenerateSummary()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
}

/// Key points section for summarized articles
struct ArticleKeyPointsSection: View {
    let keyPoints: [String]
    let fontSize: ArticleFontSize
    let lineSpacing: ArticleLineSpacing
    let appTypeface: AppTypeface

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key Points")
                .font(appTypeface.font(size: fontSize.bodyFontSize + 2, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(keyPoints, id: \.self) { point in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(appTypeface.font(size: fontSize.bodyFontSize))
                            .foregroundStyle(.blue)
                        Text(point.smartQuotes)
                            .font(appTypeface.font(size: fontSize.bodyFontSize))
                            .lineSpacing(fontSize.bodyFontSize * (lineSpacing.multiplier - 1))
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}
