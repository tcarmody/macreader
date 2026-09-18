import SwiftUI
import Combine

/// Manages scroll state for the article detail view
/// Uses ScrollViewProxy for reliable scroll-to-top and NSScrollView for page up/down
@MainActor
class ArticleScrollState: ObservableObject {
    /// Reference to the underlying NSScrollView (set by ScrollViewAccessor)
    weak var scrollView: NSScrollView?

    /// ScrollViewProxy for reliable scroll-to-top (set by ArticleDetailView)
    var scrollProxy: ScrollViewProxy?

    /// ID for the top anchor element
    static let topAnchorID = "article-top"

    /// Current scroll progress (0.0 to 1.0)
    @Published var scrollProgress: CGFloat = 0

    /// Observer for scroll position changes
    private var scrollObserver: NSObjectProtocol?
    private var pendingOffset: CGFloat?

    var offset: CGFloat { scrollView?.contentView.bounds.origin.y ?? 0 }

    func attach(_ view: NSScrollView) {
        if scrollView !== view {
            stopObservingScroll()
            scrollView = view
            scrollProgress = 0
        }
        startObservingScroll()
        updateScrollProgress()
        finishRestoringOffset()
    }

    func restoreOffset(_ offset: CGFloat) {
        pendingOffset = offset
        DispatchQueue.main.async { [weak self] in self?.finishRestoringOffset() }
    }

    func finishRestoringOffset() {
        guard let target = pendingOffset, let view = scrollView,
              let document = view.documentView else { return }
        let maximum = max(0, document.frame.height - view.contentView.bounds.height)
        view.contentView.scroll(to: NSPoint(x: 0, y: min(target, maximum)))
        view.reflectScrolledClipView(view.contentView)
        if maximum >= target { pendingOffset = nil }
        updateScrollProgress()
    }

    /// Whether we can scroll down (content below visible area)
    var canScrollDown: Bool {
        guard let scrollView = scrollView else { return false }
        let clipView = scrollView.contentView
        let documentView = scrollView.documentView

        guard let docView = documentView else { return false }

        let contentHeight = docView.frame.height
        let viewHeight = clipView.bounds.height
        let currentY = clipView.bounds.origin.y

        // Can scroll if there's content below the visible area
        return currentY + viewHeight < contentHeight - 1
    }

    /// Whether we can scroll up (content above visible area)
    var canScrollUp: Bool {
        guard let scrollView = scrollView else { return false }
        let clipView = scrollView.contentView
        return clipView.bounds.origin.y > 1
    }

    /// Scroll down by one page using NSScrollView's built-in method
    func scrollDown() {
        pendingOffset = nil
        guard let scrollView = scrollView else {
            print("scrollDown: No scroll view!")
            return
        }

        // Use NSScrollView's pageDown which handles everything correctly
        scrollView.pageDown(nil)
    }

    /// Scroll up by one page using NSScrollView's built-in method
    func scrollUp() {
        pendingOffset = nil
        guard let scrollView = scrollView else {
            print("scrollUp: No scroll view!")
            return
        }

        // Use NSScrollView's pageUp which handles everything correctly
        scrollView.pageUp(nil)
    }

    /// Reset scroll position to top using ScrollViewProxy
    func scrollToTop() {
        scrollProxy?.scrollTo(Self.topAnchorID, anchor: .top)
        scrollProgress = 0
    }

    /// Start observing scroll position changes
    func startObservingScroll() {
        guard scrollObserver == nil, let scrollView else { return }

        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateScrollProgress()
            }
        }

        // Enable bounds change notifications
        scrollView.contentView.postsBoundsChangedNotifications = true
    }

    /// Stop observing scroll position
    func stopObservingScroll() {
        if let observer = scrollObserver {
            NotificationCenter.default.removeObserver(observer)
            scrollObserver = nil
        }
    }

    /// Update the scroll progress value
    private func updateScrollProgress() {
        guard let scrollView = scrollView,
              let docView = scrollView.documentView else {
            scrollProgress = 0
            return
        }

        let clipView = scrollView.contentView
        let contentHeight = docView.frame.height
        let viewHeight = clipView.bounds.height
        let currentY = clipView.bounds.origin.y

        // Calculate scrollable range
        let scrollableHeight = contentHeight - viewHeight

        if scrollableHeight <= 0 {
            // Content fits in view, consider it 100% read
            scrollProgress = 1
        } else {
            scrollProgress = min(1, max(0, currentY / scrollableHeight))
        }
    }

    deinit {
        if let observer = scrollObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

/// Helper to find and store reference to NSScrollView for page up/down functionality
struct ScrollViewAccessor: NSViewRepresentable {
    let scrollState: ArticleScrollState

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            findScrollView(in: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            findScrollView(in: nsView)
        }
    }

    private func findScrollView(in view: NSView) {
        var current: NSView? = view
        while let v = current {
            if let scrollView = v as? NSScrollView {
                scrollState.attach(scrollView)
                return
            }
            current = v.superview
        }
    }
}
