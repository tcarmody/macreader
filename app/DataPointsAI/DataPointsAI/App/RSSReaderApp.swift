import SwiftUI

@main
struct RSSReaderApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .onAppear {
                    Task {
                        await appState.startServer()
                    }
                }
        }
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                Button("Add Feed...") {
                    DispatchQueue.main.async {
                        appState.showAddFeed = true
                    }
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()

                Button("Refresh Feeds") {
                    Task {
                        try? await appState.refreshFeeds()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            // View menu
            CommandGroup(after: .sidebar) {
                Divider()

                Button("Show All") {
                    DispatchQueue.main.async {
                        appState.selectedFilter = .all
                    }
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Show Unread") {
                    DispatchQueue.main.async {
                        appState.selectedFilter = .unread
                    }
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Show Saved") {
                    DispatchQueue.main.async {
                        appState.selectedFilter = .bookmarked
                    }
                }
                .keyboardShortcut("3", modifiers: .command)
            }

            // Article menu
            CommandMenu("Article") {
                Button("Open Original") {
                    if let article = appState.selectedArticle {
                        NSWorkspace.shared.open(article.url)
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(appState.selectedArticle == nil)

                Button("Toggle Bookmark") {
                    if let article = appState.selectedArticle {
                        Task {
                            try? await appState.toggleBookmark(articleId: article.id)
                        }
                    }
                }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(appState.selectedArticle == nil)

                Divider()

                Button("Mark as Read") {
                    if let article = appState.selectedArticle {
                        Task {
                            try? await appState.markRead(articleId: article.id, isRead: true)
                        }
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.selectedArticle == nil)

                Button("Mark as Unread") {
                    if let article = appState.selectedArticle {
                        Task {
                            try? await appState.markRead(articleId: article.id, isRead: false)
                        }
                    }
                }
                .keyboardShortcut("u", modifiers: .command)
                .disabled(appState.selectedArticle == nil)
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
        #endif
    }
}
