import SwiftUI

/// Header for the Pinned Searches section with collapse toggle
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

                Image(systemName: "pin.fill")
                    .foregroundStyle(.blue)

                Text("Pinned Searches")
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
