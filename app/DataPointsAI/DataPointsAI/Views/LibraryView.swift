import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @State private var deleteIDs: Set<Int> = []
    @State private var showDelete = false
    @State private var isDropTargeted = false

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
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .background(Color.accentColor.opacity(0.08).clipShape(RoundedRectangle(cornerRadius: 10)))
                    .overlay { Label("Drop a URL or supported document to add to Library", systemImage: "plus.circle")
                        .font(.headline).padding(16).background(.regularMaterial, in: Capsule()) }
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: dropTypes, isTargeted: $isDropTargeted, perform: handleDrop)
        // Shared identity + always-present items — see ToolbarIdentity.swift.
        .toolbar(id: mainWindowToolbarID) {
            ToolbarItem(id: "library-mark-selected", placement: .primaryAction, showsByDefault: false) {
                Button {
                    Task { await appState.markLibraryItemsRead(ids: appState.selectedLibraryItemIds, isRead: true) }
                } label: { Label("Mark Selected as Read", systemImage: "envelope.open") }
                    .helpLabel(appState.selectedLibraryItemIds.count > 1
                               ? "Mark \(appState.selectedLibraryItemIds.count) Items as Read"
                               : "Mark Selected as Read")
                    .disabled(appState.selectedLibraryItemIds.count < 2)
            }
            ToolbarItem(id: "library-filter", placement: .primaryAction, showsByDefault: true) {
                Menu {
                    Picker("Type", selection: $appState.libraryFilterType) {
                        Text("All Types").tag(nil as LibraryContentType?)
                        ForEach(LibraryContentType.allCases, id: \.self) { type in
                            Label(type.label, systemImage: type.iconName).tag(Optional(type))
                        }
                    }
                } label: { Label("Filter", systemImage: appState.libraryFilterType == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") }
                    .helpLabel("Filter by Type")
            }
            ToolbarItem(id: "library-sort", placement: .primaryAction, showsByDefault: true) {
                Menu {
                    Picker("Sort", selection: $appState.librarySortOption) {
                        ForEach(ArticleSortOption.allCases, id: \.self) { option in Text(option.label).tag(option) }
                    }
                } label: { Label("Sort", systemImage: "arrow.up.arrow.down.circle") }
                    .helpLabel("Sort: \(appState.librarySortOption.label)")
            }
            ToolbarItem(id: "library-actions", placement: .primaryAction, showsByDefault: true) {
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
            }
            ToolbarItem(id: "library-add", placement: .primaryAction, showsByDefault: true) {
                Button { appState.showAddToLibrary = true } label: { Label("Add to Library", systemImage: "plus") }
                    .helpLabel("Add to Library")
            }
        }
        .toolbarRole(.editor)
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

    private var dropTypes: [UTType] {
        [.url, .fileURL, .pdf, .plainText, .html,
         UTType(filenameExtension: "docx") ?? .data,
         UTType(filenameExtension: "md") ?? .plainText]
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSURL.self) { object, _ in
            guard let nsURL = object as? NSURL else { return }
            let url = nsURL as URL
            Task { @MainActor in await importDroppedURL(url) }
        }
        return true
    }

    @MainActor
    private func importDroppedURL(_ url: URL) async {
        if !url.isFileURL {
            guard ["http", "https"].contains(url.scheme?.lowercased()) else {
                appState.error = "Only web URLs can be added to the Library."
                return
            }
            do {
                _ = try await appState.addURLToLibrary(url: url.absoluteString)
            } catch { appState.error = error.localizedDescription }
            return
        }

        let allowedExtensions = Set(["pdf", "docx", "doc", "txt", "md", "html", "htm"])
        let ext = url.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            appState.error = "Unsupported file type. Drop a PDF, Word, text, Markdown, or HTML document."
            return
        }
        do {
            let data = try Data(contentsOf: url)
            try await appState.uploadFileToLibrary(data: data, filename: url.lastPathComponent)
        } catch { appState.error = error.localizedDescription }
    }

    @ViewBuilder private func contextMenu(_ item: LibraryItem) -> some View {
        let ids = appState.selectedLibraryItemIds.contains(item.id) ? appState.selectedLibraryItemIds : [item.id]
        let isInSelection = appState.selectedLibraryItemIds.contains(item.id)
        let count = ids.count

        if count == 1, item.type == .url {
            Button("Open in Browser", systemImage: "safari") { NSWorkspace.shared.open(item.url) }
            Divider()
        }

        Button(count > 1 ? "Mark \(count) as Read" : item.isRead ? "Mark as Unread" : "Mark as Read") {
            Task { await appState.markLibraryItemsRead(ids: ids, isRead: ids.count > 1 || !item.isRead) }
        }
        if count > 1 {
            Button("Mark \(count) as Unread") {
                Task { await appState.markLibraryItemsRead(ids: ids, isRead: false) }
            }
        } else {
            Button(item.isBookmarked ? "Remove Bookmark" : "Bookmark", systemImage: item.isBookmarked ? "bookmark.slash" : "bookmark") {
                Task {
                    do { try await appState.toggleLibraryItemBookmark(itemId: item.id) }
                    catch { appState.error = error.localizedDescription }
                }
            }
            Divider()
            if item.type == .url {
                Button("Copy Link", systemImage: "link") { copy(item.url.absoluteString) }
                ShareLink(item: item.url) { Label("Share", systemImage: "square.and.arrow.up") }
            }
            Divider()
            Button(item.summaryShort == nil ? "Summarize" : "Regenerate Summary", systemImage: item.summaryShort == nil ? "sparkles" : "arrow.clockwise") {
                Task {
                    await appState.loadLibraryItemDetail(for: item)
                    if appState.selectedLibraryItemDetail?.id == item.id { appState.pendingDetailTab = .ai }
                }
            }
            Button("Chat with Item", systemImage: "bubble.left.and.bubble.right") {
                Task {
                    await appState.loadLibraryItemDetail(for: item)
                    if appState.selectedLibraryItemDetail?.id == item.id { appState.pendingDetailTab = .chat }
                }
            }
            Button("Find Related Articles", systemImage: "link.circle") {
                Task {
                    await appState.loadLibraryItemDetail(for: item)
                    if appState.selectedLibraryItemDetail?.id == item.id { appState.pendingDetailTab = .related }
                }
            }
            Button("Send to Composer", systemImage: "paperplane") {
                Task {
                    do { try await appState.promoteLibraryItemToComposer(itemId: item.id) }
                    catch { appState.error = error.localizedDescription }
                }
            }
        }
        Divider()
        Button("Mark Above as Read", systemImage: "arrow.up.to.line") { markLibraryItems(above: item) }
        Button("Mark Below as Read", systemImage: "arrow.down.to.line") { markLibraryItems(below: item) }
        if !isInSelection {
            Divider()
            Button("Add to Selection", systemImage: "plus.circle") {
                appState.selectedLibraryItemIds.insert(item.id)
            }
        }
        Divider()
        Button("Delete…", role: .destructive) { deleteIDs = ids; showDelete = true }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func markLibraryItems(above item: LibraryItem) {
        guard let index = appState.visibleLibraryItems.firstIndex(where: { $0.id == item.id }) else { return }
        let ids = Set(appState.visibleLibraryItems[..<index].filter { !$0.isRead }.map(\.id))
        guard !ids.isEmpty else { return }
        Task { await appState.markLibraryItemsRead(ids: ids, isRead: true) }
    }

    private func markLibraryItems(below item: LibraryItem) {
        guard let index = appState.visibleLibraryItems.firstIndex(where: { $0.id == item.id }) else { return }
        let start = appState.visibleLibraryItems.index(after: index)
        let ids = Set(appState.visibleLibraryItems[start...].filter { !$0.isRead }.map(\.id))
        guard !ids.isEmpty else { return }
        Task { await appState.markLibraryItemsRead(ids: ids, isRead: true) }
    }
}
