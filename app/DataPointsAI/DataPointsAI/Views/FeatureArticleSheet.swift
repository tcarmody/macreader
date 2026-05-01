import SwiftUI

/// Sheet for marking an article as Featured. Admin-only on the web; on macOS, anyone with
/// the API key is treated as admin (so the sheet is available unconditionally).
struct FeatureArticleSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let article: Article

    @State private var note: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    private var noteCharCount: Int { note.count }
    private var isOverLimit: Bool { noteCharCount > 500 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 4) {
                    Text(article.isFeatured ? "Edit Featured note" : "Feature this story")
                        .font(.title3.weight(.semibold))
                    Text("Featured stories are visible to everyone with an account. Up to 32 at a time — older ones fall off automatically.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(article.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                if let host = article.url.host {
                    Text(host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Editorial note")
                        .font(.subheadline.weight(.medium))
                    Text("(optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(noteCharCount)/500")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(isOverLimit ? .red : .secondary)
                }
                TextEditor(text: $note)
                    .frame(minHeight: 100)
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                Text("Why is this worth featuring? Shown alongside the headline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack {
                if article.isFeatured {
                    Button(role: .destructive) {
                        Task { await unfeature() }
                    } label: {
                        Text("Unfeature")
                    }
                    .disabled(isSubmitting)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(article.isFeatured ? "Save" : "Feature") {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting || isOverLimit)
            }
        }
        .padding(24)
        .frame(width: 520, height: 420)
        .onAppear {
            note = article.featuredNote ?? ""
        }
    }

    private func save() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await appState.featureArticle(
                articleId: article.id,
                note: trimmed.isEmpty ? nil : trimmed
            )
            dismiss()
        } catch {
            errorMessage = "Couldn't feature: \(error.localizedDescription)"
        }
    }

    private func unfeature() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await appState.unfeatureArticle(articleId: article.id)
            dismiss()
        } catch {
            errorMessage = "Couldn't unfeature: \(error.localizedDescription)"
        }
    }
}
