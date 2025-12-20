import SwiftUI
import Combine

/// Vim-style keyboard shortcut actions
enum KeyboardAction: Equatable {
    case nextArticle           // j
    case previousArticle       // k
    case openArticle           // o or Enter
    case openInBrowser         // O (shift+o)
    case toggleRead            // r
    case toggleBookmark        // s (star)
    case goToTop               // g then g
    case goToBottom            // G (shift+g)
    case focusSearch           // /
    case markAllRead           // A (shift+a)
    case refresh               // R (shift+r)
    case escape                // Escape - clear selection/search
}

/// Manages vim-style keyboard navigation for the article list
///
/// ## Keyboard Shortcuts
/// - `j` - Next article
/// - `k` - Previous article
/// - `o` / `Enter` - Open article (load detail)
/// - `O` (shift+o) - Open in browser
/// - `r` - Toggle read status
/// - `R` (shift+r) - Refresh feeds
/// - `s` - Toggle bookmark (star)
/// - `g g` - Go to first article
/// - `G` (shift+g) - Go to last article
/// - `/` - Focus search field
/// - `A` (shift+a) - Mark all as read
/// - `Escape` - Clear search/selection
@MainActor
class KeyboardShortcutManager: ObservableObject {
    static let shared = KeyboardShortcutManager()

    /// Whether keyboard shortcuts are enabled
    @Published var isEnabled: Bool = true

    /// Pending key for multi-key sequences (e.g., 'g' waiting for second 'g')
    @Published private(set) var pendingKey: Character?

    /// Timer to clear pending key after timeout
    private var pendingKeyTimer: Timer?

    /// Clear pending key after 1 second
    private let pendingKeyTimeout: TimeInterval = 1.0

    private init() {}

    /// Process a key event and return the corresponding action
    /// - Parameter event: The NSEvent from key press
    /// - Returns: The keyboard action to perform, if any
    func processKeyEvent(_ event: NSEvent) -> KeyboardAction? {
        guard isEnabled else { return nil }
        guard let characters = event.charactersIgnoringModifiers else { return nil }
        guard let char = characters.first else { return nil }

        let hasShift = event.modifierFlags.contains(.shift)
        let hasCommand = event.modifierFlags.contains(.command)
        let hasControl = event.modifierFlags.contains(.control)
        let hasOption = event.modifierFlags.contains(.option)

        // Skip if command/control/option modifiers are held (let system handle those)
        if hasCommand || hasControl || hasOption {
            return nil
        }

        // Handle multi-key sequences
        if let pending = pendingKey {
            clearPendingKey()

            // 'g' followed by 'g' = go to top
            if pending == "g" && char == "g" {
                return .goToTop
            }

            // Unknown sequence, ignore
            return nil
        }

        // Handle single keys
        switch char {
        case "j":
            return .nextArticle
        case "k":
            return .previousArticle
        case "o":
            return hasShift ? .openInBrowser : .openArticle
        case "\r", "\n": // Enter/Return
            return .openArticle
        case "r":
            return hasShift ? .refresh : .toggleRead
        case "s":
            return .toggleBookmark
        case "g":
            // Start 'g' sequence, wait for next key
            startPendingKey("g")
            return nil
        case "G":
            return .goToBottom
        case "/":
            return .focusSearch
        case "A":
            return .markAllRead
        case "\u{1B}": // Escape
            return .escape
        default:
            return nil
        }
    }

    /// Start waiting for a second key in a sequence
    private func startPendingKey(_ char: Character) {
        pendingKey = char
        pendingKeyTimer?.invalidate()
        pendingKeyTimer = Timer.scheduledTimer(withTimeInterval: pendingKeyTimeout, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.clearPendingKey()
            }
        }
    }

    /// Clear the pending key state
    private func clearPendingKey() {
        pendingKey = nil
        pendingKeyTimer?.invalidate()
        pendingKeyTimer = nil
    }
}
