import SwiftUI

/// Header for the Newsletters section with collapse toggle
struct NewsletterHeader: View {
    let feedCount: Int
    let unreadCount: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                Image(systemName: "envelope.fill")
                    .foregroundStyle(.orange)

                Text("Newsletters")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer(minLength: 4)

                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
            }
            // Offset to align with feed row badges (section headers are wider than rows)
            .padding(.trailing, 12)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 4)
    }
}
