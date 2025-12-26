import SwiftUI

/// Row for Library in the sidebar
struct LibrarySidebarRow: View {
    let isSelected: Bool
    let count: Int

    var body: some View {
        Label {
            HStack {
                Text("Library")
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
        } icon: {
            Image(systemName: "books.vertical")
                .foregroundStyle(isSelected ? .blue : .secondary)
        }
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
}
