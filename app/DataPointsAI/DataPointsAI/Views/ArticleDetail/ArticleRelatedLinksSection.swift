import SwiftUI

/// Related links section showing neural search results from Exa
struct ArticleRelatedLinksSection: View {
    let relatedLinks: [RelatedLink]
    let fontSize: ArticleFontSize
    let lineSpacing: ArticleLineSpacing
    let appTypeface: AppTypeface

    let isLoadingRelated: Bool
    let relatedLinksError: String?
    let onFindRelated: () -> Void

    var body: some View {
        if !relatedLinks.isEmpty {
            relatedLinksView
        } else if isLoadingRelated {
            loadingView
        } else if let error = relatedLinksError {
            errorView(error: error)
        } else {
            findRelatedPromptView
        }
    }

    // MARK: - Related Links View

    @ViewBuilder
    private var relatedLinksView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Related Articles", systemImage: "link.badge.plus")
                    .font(appTypeface.font(size: fontSize.bodyFontSize + 2, weight: .semibold))
                    .foregroundStyle(.blue)

                Spacer()

                Text("\(relatedLinks.count)")
                    .font(appTypeface.font(size: fontSize.bodyFontSize - 1))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                ForEach(relatedLinks) { link in
                    relatedLinkRow(link: link)
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func relatedLinkRow(link: RelatedLink) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title (clickable)
            Link(destination: URL(string: link.url)!) {
                Text(link.title)
                    .font(appTypeface.font(size: fontSize.bodyFontSize, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }

            // Snippet
            if !link.snippet.isEmpty {
                Text(link.snippet)
                    .font(appTypeface.font(size: fontSize.bodyFontSize - 1))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Domain and metadata
            HStack(spacing: 8) {
                Text(link.domain)
                    .font(appTypeface.font(size: fontSize.bodyFontSize - 2))
                    .foregroundStyle(.tertiary)

                if let publishedDate = link.publishedDate {
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text(publishedDate)
                        .font(appTypeface.font(size: fontSize.bodyFontSize - 2))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Loading View

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Finding related articles...")
                .font(appTypeface.font(size: fontSize.bodyFontSize))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(error: String) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(appTypeface.font(size: fontSize.bodyFontSize - 1))
                    .foregroundStyle(.secondary)
            }

            Button("Retry") {
                onFindRelated()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Find Related Prompt View

    @ViewBuilder
    private var findRelatedPromptView: some View {
        VStack(spacing: 12) {
            Text("Discover related articles using neural search")
                .font(appTypeface.font(size: fontSize.bodyFontSize))
                .foregroundStyle(.secondary)

            Button {
                onFindRelated()
            } label: {
                Label("Find Related", systemImage: "link.badge.plus")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
