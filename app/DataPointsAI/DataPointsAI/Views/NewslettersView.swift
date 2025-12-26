import SwiftUI

/// Middle pane: newsletters list (imported email newsletters)
struct NewslettersView: View {
    @EnvironmentObject var appState: AppState
    @State private var listSelection: Set<LibraryItem.ID> = []

    var body: some View {
        Group {
            if appState.isLoading && appState.newsletterItems.isEmpty {
                ProgressView("Loading newsletters...")
            } else if appState.newsletterItems.isEmpty {
                EmptyNewslettersView()
            } else {
                newsletterList
            }
        }
        .navigationTitle("Newsletters")
        .onChange(of: listSelection) { oldSelection, newSelection in
            handleSelectionChange(from: oldSelection, to: newSelection)
        }
        .toolbar {
            ToolbarItemGroup {
                // Refresh newsletters
                Button {
                    Task {
                        await appState.loadNewsletterItems()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Newsletters")

                // Open settings
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Image(systemName: "gear")
                }
                .help("Newsletter Settings")
            }
        }
        .onAppear {
            Task {
                await appState.loadNewsletterItems()
            }
        }
    }

    private var newsletterList: some View {
        List(selection: $listSelection) {
            ForEach(appState.newsletterItems) { item in
                NewsletterItemRow(item: item)
                    .tag(item.id)
                    .contextMenu {
                        itemContextMenu(for: item)
                    }
            }
        }
        .listStyle(.inset)
    }

    private func handleSelectionChange(from oldSelection: Set<LibraryItem.ID>, to newSelection: Set<LibraryItem.ID>) {
        // If exactly one item is selected, load its detail
        if newSelection.count == 1, let selectedId = newSelection.first {
            if let item = appState.newsletterItems.first(where: { $0.id == selectedId }) {
                appState.selectedLibraryItem = item
                Task {
                    await appState.loadLibraryItemDetail(for: item)
                }
            }
        } else if newSelection.isEmpty {
            appState.selectedLibraryItem = nil
        }
    }

    @ViewBuilder
    private func itemContextMenu(for item: LibraryItem) -> some View {
        Button {
            Task {
                try? await appState.toggleLibraryItemBookmark(itemId: item.id)
            }
        } label: {
            Label(item.isBookmarked ? "Remove Bookmark" : "Bookmark", systemImage: item.isBookmarked ? "star.fill" : "star")
        }

        Button {
            Task {
                try? await appState.markLibraryItemRead(itemId: item.id, isRead: !item.isRead)
            }
        } label: {
            Label(item.isRead ? "Mark as Unread" : "Mark as Read", systemImage: item.isRead ? "envelope.badge" : "envelope.open")
        }

        Divider()

        Button {
            Task {
                try? await appState.summarizeLibraryItem(itemId: item.id)
            }
        } label: {
            Label("Summarize", systemImage: "sparkles")
        }

        Divider()

        Button(role: .destructive) {
            Task {
                try? await appState.deleteLibraryItem(itemId: item.id)
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

/// Row for a newsletter item
struct NewsletterItemRow: View {
    let item: LibraryItem
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            // Newsletter icon
            Image(systemName: "envelope.open")
                .font(.title2)
                .foregroundStyle(item.isRead ? Color.secondary : Color.orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                // Title (subject line)
                Text(item.displayName)
                    .font(appState.settings.listDensity == .compact ? .subheadline : .headline)
                    .fontWeight(item.isRead ? .regular : .semibold)
                    .foregroundStyle(item.isRead ? .secondary : .primary)
                    .lineLimit(appState.settings.listDensity == .compact ? 1 : 2)

                // Summary preview if available
                if let summary = item.summaryShort, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(appState.settings.listDensity == .compact ? 1 : 2)
                }

                // Metadata row
                HStack(spacing: 8) {
                    Text("Newsletter")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.7))
                        .clipShape(Capsule())

                    Text(item.timeAgo)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if item.isBookmarked {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }

                    if item.summaryShort != nil {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, appState.settings.listDensity == .compact ? 4 : 8)
        .contentShape(Rectangle())
    }
}

/// Empty state for newsletters
struct EmptyNewslettersView: View {
    var body: some View {
        VStack(spacing: 24) {
            // Newsletter illustration
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 120, height: 120)

                // Envelope stack
                ZStack {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange.opacity(0.4))
                        .offset(x: 8, y: 8)

                    Image(systemName: "envelope.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange.opacity(0.6))
                        .offset(x: 4, y: 4)

                    Image(systemName: "envelope.open.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                }
            }

            VStack(spacing: 8) {
                Text("No Newsletters")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Set up Mail.app integration to automatically import newsletter emails for reading and summarization.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            Button {
                // Open settings to newsletter section
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Label("Set Up Newsletters", systemImage: "gear")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NewslettersView()
        .environmentObject(AppState())
        .frame(width: 350)
}
