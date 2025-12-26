import SwiftUI

/// Row for Newsletters in the sidebar
struct NewslettersSidebarRow: View {
    let isSelected: Bool
    let count: Int

    var body: some View {
        Label {
            HStack {
                Text("Newsletters")
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
            Image(systemName: "envelope.open")
                .foregroundStyle(isSelected ? .blue : .secondary)
        }
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
}
