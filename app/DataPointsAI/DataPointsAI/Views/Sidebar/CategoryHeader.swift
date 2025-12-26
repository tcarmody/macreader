import SwiftUI

/// Header for a category section with collapse toggle
struct CategoryHeader: View {
    let category: String
    let feedCount: Int
    let unreadCount: Int
    let isCollapsed: Bool
    let onToggle: () -> Void
    var isDropTarget: Bool = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                Image(systemName: "folder.fill")
                    .foregroundStyle(.yellow)

                Text(category)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer(minLength: 4)

                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple)
                        .clipShape(Capsule())
                }
            }
            // Offset to align with feed row badges (section headers are wider than rows)
            .padding(.trailing, 12)
            .padding(.vertical, 2)
            .background(isDropTarget ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 4)
    }
}

/// Header for uncategorized feeds section with drop target support
struct UncategorizedHeader: View {
    var isDropTarget: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text("Feeds")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.vertical, 2)
        .background(isDropTarget ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
    }
}
