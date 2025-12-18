import SwiftUI

/// Reusable search bar component
struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search"
    var onCommit: (() -> Void)?

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit {
                    onCommit?()
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Keyboard shortcut modifier for search
struct SearchShortcut: ViewModifier {
    @FocusState.Binding var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .keyboardShortcut("/", modifiers: [])
            .onAppear {
                // Register keyboard shortcut handler
            }
    }
}

#Preview {
    @Previewable @State var searchText = ""

    SearchBar(text: $searchText, placeholder: "Search articles")
        .padding()
        .frame(width: 300)
}
