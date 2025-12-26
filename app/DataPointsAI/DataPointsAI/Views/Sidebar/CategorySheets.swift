import SwiftUI

/// Make String conform to Identifiable for sheet binding
extension String: @retroactive Identifiable {
    public var id: String { self }
}

/// Sheet for creating a new category and moving feeds to it
struct NewCategorySheet: View {
    let feedIds: [Int]
    let onDismiss: () -> Void
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 20) {
            Text("New Folder")
                .font(.headline)

            TextField("Folder Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            HStack {
                Button("Cancel") {
                    onDismiss()
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Create") {
                    save()
                }
                .keyboardShortcut(.return)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
        .padding()
        .frame(width: 350)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        isSaving = true
        Task {
            for feedId in feedIds {
                try? await appState.moveFeedToCategory(feedId: feedId, category: trimmedName)
            }
            onDismiss()
            dismiss()
        }
    }
}

/// Sheet for renaming a category
struct RenameCategorySheet: View {
    let category: String
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Rename Folder")
                .font(.headline)

            TextField("Folder Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.return)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
        .padding()
        .frame(width: 350)
        .onAppear {
            name = category
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, trimmedName != category else {
            dismiss()
            return
        }

        isSaving = true
        Task {
            do {
                try await appState.renameCategory(from: category, to: trimmedName)
                dismiss()
            } catch {
                print("Failed to rename category: \(error)")
            }
            isSaving = false
        }
    }
}
