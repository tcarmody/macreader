import SwiftUI

/// Header for the Saved Searches section with collapse toggle
struct SavedSearchesHeader: View {
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                Image(systemName: "bookmark.fill")
                    .foregroundStyle(.blue)

                Text("Saved Searches")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer(minLength: 4)
            }
            .padding(.trailing, 12)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 4)
    }
}
