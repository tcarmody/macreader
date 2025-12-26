import SwiftUI

/// Sheet for editing a feed's name
struct EditFeedView: View {
    let feed: Feed
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Rename Feed")
                .font(.headline)

            TextField("Feed Name", text: $name)
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
            name = feed.name
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        isSaving = true
        Task {
            do {
                try await appState.updateFeed(feedId: feed.id, name: trimmedName)
                dismiss()
            } catch {
                // Handle error - could show an alert
                print("Failed to update feed: \(error)")
            }
            isSaving = false
        }
    }
}
