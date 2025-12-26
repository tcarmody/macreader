import Foundation
import WebKit

/// Fetches web pages using WKWebView to leverage Safari's cookie store.
/// This allows fetching content from sites where the user is logged in via Safari.
@MainActor
final class AuthenticatedFetcher: NSObject {

    /// Result of an authenticated fetch operation
    struct FetchResult {
        let html: String
        let finalURL: URL
        let success: Bool
        let error: String?
    }

    /// Configuration for the fetcher
    struct Config {
        /// Timeout in seconds for page load
        var timeout: TimeInterval = 45

        /// Additional time to wait after page load for JS rendering
        var postLoadDelay: TimeInterval = 2.0

        /// Whether to scroll page to trigger lazy loading
        var scrollToLoadContent: Bool = true

        /// Number of scroll iterations to perform
        var scrollIterations: Int = 3

        /// Delay between scroll iterations
        var scrollDelay: TimeInterval = 0.5
    }

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<FetchResult, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var config: Config

    init(config: Config = Config()) {
        self.config = config
        super.init()
    }

    /// Fetch a URL using Safari's authentication cookies
    /// - Parameter url: The URL to fetch
    /// - Returns: FetchResult containing the page HTML or error
    func fetch(url: URL) async -> FetchResult {
        // Clean up any previous state
        cleanup()

        return await withCheckedContinuation { continuation in
            self.continuation = continuation

            // Create WebView configuration that uses default (shared) data store
            // This shares cookies with Safari on macOS
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = WKWebsiteDataStore.default()

            // Set preferences
            let preferences = WKWebpagePreferences()
            preferences.allowsContentJavaScript = true
            configuration.defaultWebpagePreferences = preferences

            // Create the web view (hidden, not added to any view hierarchy)
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 800), configuration: configuration)
            webView.navigationDelegate = self
            webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

            self.webView = webView

            // Set up timeout
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(self?.config.timeout ?? 30) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.handleTimeout()
            }

            // Start loading
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }

    private func handleTimeout() {
        guard let continuation = self.continuation else { return }
        self.continuation = nil

        let result = FetchResult(
            html: "",
            finalURL: webView?.url ?? URL(string: "about:blank")!,
            success: false,
            error: "Request timed out after \(Int(config.timeout)) seconds"
        )

        cleanup()
        continuation.resume(returning: result)
    }

    private func cleanup() {
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
    }

    private func extractHTML() {
        guard let webView = webView, let continuation = self.continuation else { return }
        self.continuation = nil

        Task { [weak self] in
            guard let self = self, self.webView != nil else {
                continuation.resume(returning: FetchResult(
                    html: "",
                    finalURL: URL(string: "about:blank")!,
                    success: false,
                    error: "WebView was deallocated"
                ))
                return
            }

            // Scroll the page to trigger lazy loading of content
            if self.config.scrollToLoadContent, let webView = self.webView {
                await self.scrollToLoadAllContent(webView: webView)
            }

            // Wait for any final JavaScript to execute
            try? await Task.sleep(nanoseconds: UInt64(self.config.postLoadDelay * 1_000_000_000))

            guard let webView = self.webView else {
                continuation.resume(returning: FetchResult(
                    html: "",
                    finalURL: URL(string: "about:blank")!,
                    success: false,
                    error: "WebView was deallocated"
                ))
                return
            }

            // Extract the full document HTML
            let js = "document.documentElement.outerHTML"

            do {
                let html = try await webView.evaluateJavaScript(js) as? String ?? ""
                let finalURL = webView.url ?? URL(string: "about:blank")!

                self.cleanup()

                continuation.resume(returning: FetchResult(
                    html: html,
                    finalURL: finalURL,
                    success: !html.isEmpty,
                    error: html.isEmpty ? "No HTML content extracted" : nil
                ))
            } catch {
                self.cleanup()

                continuation.resume(returning: FetchResult(
                    html: "",
                    finalURL: webView.url ?? URL(string: "about:blank")!,
                    success: false,
                    error: "Failed to extract HTML: \(error.localizedDescription)"
                ))
            }
        }
    }

    /// Scroll down the page to trigger lazy loading of content
    private func scrollToLoadAllContent(webView: WKWebView) async {
        // JavaScript to scroll incrementally through the page
        // This simulates user scrolling which triggers lazy loading better than jumping to bottom
        let incrementalScrollScript = """
            (function() {
                const viewportHeight = window.innerHeight;
                const docHeight = Math.max(
                    document.body.scrollHeight,
                    document.documentElement.scrollHeight
                );
                const currentScroll = window.scrollY;
                const nextScroll = Math.min(currentScroll + viewportHeight * 0.8, docHeight);

                window.scrollTo({ top: nextScroll, behavior: 'instant' });

                return {
                    current: nextScroll,
                    total: docHeight,
                    done: nextScroll >= docHeight - viewportHeight
                };
            })()
        """

        let scrollToTopScript = "window.scrollTo(0, 0)"

        // Scroll through the entire page incrementally
        for _ in 0..<20 { // Max 20 scroll steps
            let result = try? await webView.evaluateJavaScript(incrementalScrollScript)

            // Wait for content to load after each scroll
            try? await Task.sleep(nanoseconds: UInt64(config.scrollDelay * 1_000_000_000))

            // Check if we've reached the bottom
            if let dict = result as? [String: Any],
               let done = dict["done"] as? Bool,
               done {
                break
            }
        }

        // Additional wait at the bottom for any final lazy content
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Scroll back to top
        _ = try? await webView.evaluateJavaScript(scrollToTopScript)

        // Wait for content to stabilize
        await waitForContentStability(webView: webView)
    }

    /// Wait until the page content stops changing (indicates lazy loading is complete)
    private func waitForContentStability(webView: WKWebView, maxWait: TimeInterval = 3.0) async {
        let getContentLength = """
            document.body.innerHTML.length
        """

        var lastLength = 0
        var stableCount = 0
        let checkInterval: UInt64 = 300_000_000 // 300ms
        let maxChecks = Int(maxWait / 0.3)

        for _ in 0..<maxChecks {
            if let length = try? await webView.evaluateJavaScript(getContentLength) as? Int {
                if length == lastLength {
                    stableCount += 1
                    // Content hasn't changed for 2 checks (~600ms), consider it stable
                    if stableCount >= 2 {
                        break
                    }
                } else {
                    stableCount = 0
                    lastLength = length
                }
            }

            try? await Task.sleep(nanoseconds: checkInterval)
        }
    }
}

// MARK: - WKNavigationDelegate

extension AuthenticatedFetcher: WKNavigationDelegate {

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.timeoutTask?.cancel()
            self.extractHTML()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.handleNavigationError(error)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.handleNavigationError(error)
        }
    }

    private func handleNavigationError(_ error: Error) {
        guard let continuation = self.continuation else { return }
        self.continuation = nil

        timeoutTask?.cancel()

        let result = FetchResult(
            html: "",
            finalURL: webView?.url ?? URL(string: "about:blank")!,
            success: false,
            error: "Navigation failed: \(error.localizedDescription)"
        )

        cleanup()
        continuation.resume(returning: result)
    }

    nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // Allow all navigation - we want to follow redirects
        decisionHandler(.allow)
    }

    nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        // Check for HTTP errors
        if let httpResponse = navigationResponse.response as? HTTPURLResponse {
            if httpResponse.statusCode >= 400 {
                Task { @MainActor in
                    guard let continuation = self.continuation else {
                        decisionHandler(.cancel)
                        return
                    }
                    self.continuation = nil
                    self.timeoutTask?.cancel()

                    let result = FetchResult(
                        html: "",
                        finalURL: webView.url ?? URL(string: "about:blank")!,
                        success: false,
                        error: "HTTP error: \(httpResponse.statusCode)"
                    )

                    self.cleanup()
                    continuation.resume(returning: result)
                }
                decisionHandler(.cancel)
                return
            }
        }

        decisionHandler(.allow)
    }
}
