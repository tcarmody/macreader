import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @State private var deleteIDs: Set<Int> = []
    @State private var showDelete = false

    var body: some View {
        VStack(spacing: 0) {
            if !appState.searchQuery.isEmpty || appState.libraryFilterType != nil {
                HStack {
                    Text("\(appState.visibleLibraryItems.count) results in Library")
                    Spacer()
                    Button("Clear Filters") {
                        appState.searchQuery = ""
                        appState.libraryFilterType = nil
                    }.buttonStyle(.borderless)
                }
                .font(.caption).foregroundStyle(.secondary).padding(10).background(.bar)
            }
            Group {
                if appState.isLoadingLibrary {
                    ProgressView("Loading library…")
                } else if appState.visibleLibraryItems.isEmpty {
                    emptyView
                } else {
                    ScrollViewReader { proxy in
                        List(selection: $appState.selectedLibraryItemIds) {
                            ForEach(appState.visibleLibraryItems) { item in
                                ReaderRow(title: item.displayName, source: item.type == .url ? (item.url.host ?? "URL") : item.type.label,
                                    sourceSymbol: item.type.iconName, time: item.timeAgo, preview: item.summaryShort,
                                    isRead: item.isRead, isBookmarked: item.isBookmarked, hasSummary: item.summaryShort != nil)
                                    .tag(item.id).id(item.id)
                                    .contextMenu { contextMenu(item) }
                            }
                        }
                        .listStyle(.inset)
                        .onChange(of: appState.selectedLibraryItem?.id) { _, id in
                            if let id { proxy.scrollTo(id) }
                        }
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Library")
        .navigationSubtitle(appState.statusSubtitle ?? "")
        .refreshable { await appState.loadLibraryItems() }
        .onChange(of: appState.selectedLibraryItemIds) { _, ids in appState.setLibrarySelection(ids) }
        .onChange(of: appState.libraryFilterType) { _, _ in
            appState.selectedLibraryItemIds.formIntersection(Set(appState.visibleLibraryItems.map(\.id)))
        }
        .onAppear { appState.setLibrarySelection(appState.selectedLibraryItemIds) }
        .toolbar {
            ToolbarItemGroup {
                if appState.selectedLibraryItemIds.count > 1 {
                    Button {
                        Task { await appState.markLibraryItemsRead(ids: appState.selectedLibraryItemIds, isRead: true) }
                    } label: { Label("Mark Selected as Read", systemImage: "envelope.open") }
                        .helpLabel("Mark \(appState.selectedLibraryItemIds.count) Items as Read")
                }
                Menu {
                    Picker("Type", selection: $appState.libraryFilterType) {
                        Text("All Types").tag(nil as LibraryContentType?)
                        ForEach(LibraryContentType.allCases, id: \.self) { type in
                            Label(type.label, systemImage: type.iconName).tag(Optional(type))
                        }
                    }
                } label: { Label("Filter", systemImage: appState.libraryFilterType == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") }
                    .helpLabel("Filter by Type")
                Menu {
                    Picker("Sort", selection: $appState.librarySortOption) {
                        ForEach(ArticleSortOption.allCases, id: \.self) { option in Text(option.label).tag(option) }
                    }
                } label: { Label("Sort", systemImage: "arrow.up.arrow.down.circle") }
                    .helpLabel("Sort: \(appState.librarySortOption.label)")
                Menu {
                    Button("Select All") { appState.selectedLibraryItemIds = Set(appState.visibleLibraryItems.map(\.id)) }
                        .keyboardShortcut("a", modifiers: .command)
                    Button("Clear Selection") { appState.selectedLibraryItemIds.removeAll() }
                        .disabled(appState.selectedLibraryItemIds.isEmpty)
                    Button("Mark All as Read") {
                        Task { await appState.markLibraryItemsRead(ids: Set(appState.visibleLibraryItems.map(\.id)), isRead: true) }
                    }
                    Divider()
                    Button("Delete Selected…", role: .destructive) {
                        deleteIDs = appState.selectedLibraryItemIds
                        showDelete = true
                    }.disabled(appState.selectedLibraryItemIds.isEmpty)
                } label: { Label("Library Actions", systemImage: "ellipsis.circle") }.helpLabel("Library Actions")
                Button { appState.showAddToLibrary = true } label: { Label("Add to Library", systemImage: "plus") }
                    .helpLabel("Add to Library")
            }
        }
        .alert("Delete \(deleteIDs.count) Library Items?", isPresented: $showDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                let ids = deleteIDs
                Task {
                    do { for id in ids { try await appState.deleteLibraryItem(itemId: id) } }
                    catch { appState.error = error.localizedDescription }
                }
            }
        } message: { Text("Their saved content will be deleted.") }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label(appState.libraryItemCount == 0 ? "Library Empty" : "No Matching Items", systemImage: "books.vertical")
        } description: {
            Text(appState.libraryItemCount == 0 ? "Add a URL or document to read it here." : "Try another search or content type.")
        } actions: {
            if appState.libraryItemCount == 0 {
                Button("Add to Library") { appState.showAddToLibrary = true }
            } else {
                Button("Clear Filters") { appState.searchQuery = ""; appState.libraryFilterType = nil }
            }
        }
    }

    @ViewBuilder private func contextMenu(_ item: LibraryItem) -> some View {
        let ids = appState.selectedLibraryItemIds.contains(item.id) ? appState.selectedLibraryItemIds : [item.id]
        Button(ids.count > 1 ? "Mark \(ids.count) as Read" : item.isRead ? "Mark as Unread" : "Mark as Read") {
            Task { await appState.markLibraryItemsRead(ids: ids, isRead: ids.count > 1 || !item.isRead) }
        }
        if ids.count > 1 {
            Button("Mark \(ids.count) as Unread") {
                Task { await appState.markLibraryItemsRead(ids: ids, isRead: false) }
            }
        } else {
            Button(item.isBookmarked ? "Remove Bookmark" : "Bookmark", systemImage: "bookmark") {
                Task {
                    do { try await appState.toggleLibraryItemBookmark(itemId: item.id) }
                    catch { appState.error = error.localizedDescription }
                }
            }
            Button("Summary", systemImage: "sparkles") {
                Task {
                    await appState.loadLibraryItemDetail(for: item)
                    if appState.selectedLibraryItemDetail?.id == item.id { appState.pendingDetailTab = .ai }
                }
            }
            if item.type == .url {
                Button("Open in Browser", systemImage: "safari") { NSWorkspace.shared.open(item.url) }
            }
        }
        Divider()
        Button("Delete…", role: .destructive) { deleteIDs = ids; showDelete = true }
    }
}
