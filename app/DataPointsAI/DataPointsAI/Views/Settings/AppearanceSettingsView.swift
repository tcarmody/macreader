import SwiftUI

/// Appearance settings tab
struct AppearanceSettingsView: View {
    @Binding var articleFontSize: ArticleFontSize
    @Binding var articleLineSpacing: ArticleLineSpacing
    @Binding var listDensity: ListDensity
    @Binding var appTypeface: AppTypeface
    @Binding var contentTypeface: ContentTypeface
    @Binding var articleTheme: ArticleTheme
    @Binding var readerModeFontSize: ArticleFontSize
    @Binding var readerModeLineSpacing: ArticleLineSpacing

    var body: some View {
        Form {
            Section {
                // Theme picker with visual previews
                VStack(alignment: .leading, spacing: 8) {
                    Text("Theme")
                        .font(.headline)

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(ArticleTheme.allCases, id: \.self) { theme in
                            ThemePreviewButton(
                                theme: theme,
                                isSelected: articleTheme == theme,
                                action: { articleTheme = theme }
                            )
                        }
                    }
                }
                .padding(.vertical, 4)

                Text(articleTheme.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Article Theme")
            }

            Section {
                Picker("App typeface", selection: $appTypeface) {
                    ForEach(AppTypeface.allCases, id: \.self) { typeface in
                        Text(typeface.label)
                            .font(typeface.font(size: 13))
                            .tag(typeface)
                    }
                }

                Picker("Content typeface", selection: $contentTypeface) {
                    ForEach(ContentTypeface.allCases, id: \.self) { typeface in
                        Text(typeface.label).tag(typeface)
                    }
                }

                Text("App typeface is used for titles, summaries, and key points. Content typeface is used for the original HTML article content.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Typeface")
            }

            Section {
                Picker("Font size", selection: $articleFontSize) {
                    ForEach(ArticleFontSize.allCases, id: \.self) { size in
                        Text(size.label).tag(size)
                    }
                }

                Picker("Line spacing", selection: $articleLineSpacing) {
                    ForEach(ArticleLineSpacing.allCases, id: \.self) { spacing in
                        Text(spacing.label).tag(spacing)
                    }
                }
            } header: {
                Text("Size & Spacing")
            }

            Section {
                Picker("Font size", selection: $readerModeFontSize) {
                    ForEach(ArticleFontSize.allCases, id: \.self) { size in
                        Text(size.label).tag(size)
                    }
                }

                Picker("Line spacing", selection: $readerModeLineSpacing) {
                    ForEach(ArticleLineSpacing.allCases, id: \.self) { spacing in
                        Text(spacing.label).tag(spacing)
                    }
                }

                Text("Reader mode (f) hides the sidebar and article list for distraction-free reading.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Reader Mode")
            }

            Section {
                Picker("List density", selection: $listDensity) {
                    ForEach(ListDensity.allCases, id: \.self) { density in
                        Text(density.label).tag(density)
                    }
                }

                Text(listDensityDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Article List")
            }

            Section {
                // Preview of current settings
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sample Article Title")
                        .font(appTypeface.font(size: articleFontSize.titleFontSize, weight: .bold))

                    Text("This is a preview of how article content will appear with your current font and spacing settings.")
                        .font(appTypeface.font(size: articleFontSize.bodyFontSize))
                        .lineSpacing(articleFontSize.bodyFontSize * (articleLineSpacing.multiplier - 1))
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            } header: {
                Text("Preview")
            }
        }
        .formStyle(.grouped)
    }

    private var listDensityDescription: String {
        switch listDensity {
        case .compact:
            return "More articles visible, no preview text"
        case .comfortable:
            return "Balanced view with summary previews"
        case .spacious:
            return "Easy reading with extra spacing"
        }
    }
}


// MARK: - Theme Preview Button

/// Visual button for selecting an article theme
struct ThemePreviewButton: View {
    let theme: ArticleTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                // Theme preview swatch
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.backgroundColor)
                        .frame(height: 50)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    isSelected ? Color.accentColor : Color(.separatorColor),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )

                    // Sample text lines
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.textColor)
                            .frame(width: 40, height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.secondaryTextColor)
                            .frame(width: 30, height: 3)
                    }
                }

                // Theme label
                Text(theme.label)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
