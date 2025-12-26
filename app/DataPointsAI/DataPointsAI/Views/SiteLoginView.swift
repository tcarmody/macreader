import SwiftUI
import WebKit

/// A view that presents a WebView for logging into paywalled sites.
/// The session persists in the app's cookie store for future authenticated fetches.
struct SiteLoginView: View {
    @Environment(\.dismiss) private var dismiss

    /// The URL to load for login (usually the site's login page or homepage)
    let initialURL: URL

    /// Title shown in the toolbar
    let siteTitle: String

    @State private var currentURL: URL?
    @State private var isLoading: Bool = true
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false

    /// Callback when user indicates they're done logging in
    var onComplete: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with navigation and done button
            HStack(spacing: 12) {
                // Navigation buttons
                Button {
                    NotificationCenter.default.post(name: .siteLoginGoBack, object: nil)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!canGoBack)
                .buttonStyle(.borderless)

                Button {
                    NotificationCenter.default.post(name: .siteLoginGoForward, object: nil)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!canGoForward)
                .buttonStyle(.borderless)

                Button {
                    NotificationCenter.default.post(name: .siteLoginReload, object: nil)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)

                Divider()
                    .frame(height: 16)

                // URL display
                if let url = currentURL {
                    HStack(spacing: 4) {
                        if url.scheme == "https" {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                        Text(url.host ?? url.absoluteString)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundStyle(.secondary)
                    .font(.callout)
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                }

                Button("Done") {
                    onComplete?()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // WebView
            LoginWebViewRepresentable(
                initialURL: initialURL,
                currentURL: $currentURL,
                isLoading: $isLoading,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward
            )
        }
        .frame(minWidth: 800, minHeight: 600)
        .navigationTitle("Log in to \(siteTitle)")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let siteLoginGoBack = Notification.Name("siteLoginGoBack")
    static let siteLoginGoForward = Notification.Name("siteLoginGoForward")
    static let siteLoginReload = Notification.Name("siteLoginReload")
}

// MARK: - WebView Representable

struct LoginWebViewRepresentable: NSViewRepresentable {
    let initialURL: URL
    @Binding var currentURL: URL?
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool

    func makeNSView(context: Context) -> WKWebView {
        let webView = AuthenticatedFetcher.createLoginWebView()
        webView.navigationDelegate = context.coordinator

        // Load the initial URL
        let request = URLRequest(url: initialURL)
        webView.load(request)

        // Set up notification observers for navigation
        context.coordinator.setupNavigationObservers(for: webView)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Update bindings from webView state
        DispatchQueue.main.async {
            currentURL = webView.url
            canGoBack = webView.canGoBack
            canGoForward = webView.canGoForward
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: LoginWebViewRepresentable
        weak var webView: WKWebView?
        private var observers: [NSObjectProtocol] = []

        init(_ parent: LoginWebViewRepresentable) {
            self.parent = parent
        }

        deinit {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func setupNavigationObservers(for webView: WKWebView) {
            self.webView = webView

            let backObserver = NotificationCenter.default.addObserver(
                forName: .siteLoginGoBack,
                object: nil,
                queue: .main
            ) { [weak webView] _ in
                webView?.goBack()
            }

            let forwardObserver = NotificationCenter.default.addObserver(
                forName: .siteLoginGoForward,
                object: nil,
                queue: .main
            ) { [weak webView] _ in
                webView?.goForward()
            }

            let reloadObserver = NotificationCenter.default.addObserver(
                forName: .siteLoginReload,
                object: nil,
                queue: .main
            ) { [weak webView] _ in
                webView?.reload()
            }

            observers = [backObserver, forwardObserver, reloadObserver]
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.currentURL = webView.url
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }
    }
}

#Preview {
    SiteLoginView(
        initialURL: URL(string: "https://www.bloomberg.com")!,
        siteTitle: "Bloomberg"
    )
}
