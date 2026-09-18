import SwiftUI

struct LibraryItemDetailView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var scrollState: ArticleScrollState

    var body: some View {
        Group {
            if let item = appState.selectedLibraryItemDetail {
                ReaderDetailView(item: ReaderItem(libraryItem: item), scrollState: scrollState)
                    .id("library-\(item.id)")
            } else if appState.isLoadingLibraryDetail {
                ProgressView("Loading item…")
            } else {
                ContentUnavailableView(
                    appState.selectedLibraryItemIds.count > 1 ? "\(appState.selectedLibraryItemIds.count) Items Selected" : "Select an Item",
                    systemImage: "books.vertical",
                    description: Text("Choose an item to read, summarize, or discuss.")
                )
            }
        }
    }
}
