import SwiftUI

/// Middle pane: library items list
struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @State private var listSelection: Set<LibraryItem.ID> = []
    @State private var filterType: String? = nil

    var body: some View {
        Group {
            if appState.isLoading && appState.libraryItems.isEmpty {
                ProgressView("Loading library...")
            } else if filteredItems.isEmpty {
                EmptyLibraryView()
            } else {
                libraryList
            }
        }
        .navigationTitle("Library")
        .onChange(of: listSelection) { oldSelection, newSelection in
            handleSelectionChange(from: oldSelection, to: newSelection)
        }
        .toolbar {
            ToolbarItemGroup {
                // Filter by type
                Menu {
                    Button {
                        filterType = nil
                    } label: {
                        HStack {
                            if filterType == nil {
                                Image(systemName: "checkmark")
                            }
                            Text("All Types")
                        }
                    }

                    Divider()

                    ForEach(LibraryContentType.allCases, id: \.self) { type in
                        Button {
                            filterType = type.rawValue
                        } label: {
                            HStack {
                                if filterType == type.rawValue {
                                    Image(systemName: "checkmark")
                                }
                                Label(type.label, systemImage: type.iconName)
                            }
                        }
                    }
                } label: {
                    Image(systemName: filterType != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .help(filterType != nil ? "Filtering by \(LibraryContentType(rawValue: filterType!)?.label ?? "")" : "Filter by Type")

                // Add to library button
                Button {
                    appState.showAddToLibrary = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add to Library")
            }
        }
    }

    private var filteredItems: [LibraryItem] {
        if let type = filterType {
            return appState.libraryItems.filter { $0.contentType == type }
        }
        return appState.libraryItems
    }

    private var libraryList: some View {
        List(selection: $listSelection) {
            ForEach(filteredItems) { item in
                LibraryItemRow(item: item)
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
            if let item = appState.libraryItems.first(where: { $0.id == selectedId }) {
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

/// Row for a library item
struct LibraryItemRow: View {
    let item: LibraryItem
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: item.type.iconName)
                .font(.title2)
                .foregroundStyle(item.isRead ? Color.secondary : Color.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                // Title
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
                    Text(item.type.label)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.7))
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

/// Empty state for library with custom illustration
struct EmptyLibraryView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            // Library illustration
            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(0.1))
                    .frame(width: 120, height: 120)

                // Stack of books
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(bookColor(for: i))
                            .frame(width: 12, height: 50 - CGFloat(i * 5))
                    }
                }

                // Bookshelf
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.brown.opacity(0.4))
                    .frame(width: 60, height: 4)
                    .offset(y: 27)

                // Plus badge
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.indigo)
                    .offset(x: 35, y: 25)
            }

            VStack(spacing: 8) {
                Text("Library Empty")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Add URLs or upload files to save them for later reading and summarization.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            Button {
                appState.showAddToLibrary = true
            } label: {
                Label("Add to Library", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bookColor(for index: Int) -> Color {
        let colors: [Color] = [.indigo.opacity(0.6), .purple.opacity(0.5), .blue.opacity(0.5)]
        return colors[index % colors.count]
    }
}

#Preview {
    LibraryView()
        .environmentObject(AppState())
        .frame(width: 350)
}
