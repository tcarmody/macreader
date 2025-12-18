import SwiftUI
import WebKit

/// A SwiftUI view that renders HTML content using WKWebView
struct HTMLContentView: NSViewRepresentable {
    let html: String
    @Binding var dynamicHeight: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        // Disable scrolling - let parent ScrollView handle it
        webView.enclosingScrollView?.hasVerticalScroller = false
        webView.enclosingScrollView?.hasHorizontalScroller = false

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let styledHTML = wrapHTMLWithStyles(html)
        webView.loadHTMLString(styledHTML, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func wrapHTMLWithStyles(_ content: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                :root {
                    color-scheme: light dark;
                }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    font-size: 14px;
                    line-height: 1.6;
                    color: var(--text-color, #333);
                    background: transparent;
                    margin: 0;
                    padding: 0;
                    word-wrap: break-word;
                    overflow-wrap: break-word;
                }
                @media (prefers-color-scheme: dark) {
                    body {
                        --text-color: #e0e0e0;
                    }
                    a {
                        color: #6cb6ff;
                    }
                }
                @media (prefers-color-scheme: light) {
                    body {
                        --text-color: #333;
                    }
                    a {
                        color: #0066cc;
                    }
                }
                img {
                    max-width: 100%;
                    height: auto;
                    border-radius: 4px;
                }
                pre, code {
                    background: rgba(128, 128, 128, 0.1);
                    border-radius: 4px;
                    padding: 2px 6px;
                    font-family: "SF Mono", Monaco, Menlo, monospace;
                    font-size: 13px;
                }
                pre {
                    padding: 12px;
                    overflow-x: auto;
                }
                pre code {
                    padding: 0;
                    background: none;
                }
                blockquote {
                    border-left: 3px solid rgba(128, 128, 128, 0.4);
                    margin: 16px 0;
                    padding-left: 16px;
                    color: rgba(128, 128, 128, 0.9);
                }
                h1, h2, h3, h4, h5, h6 {
                    margin-top: 24px;
                    margin-bottom: 12px;
                    font-weight: 600;
                }
                h1 { font-size: 1.5em; }
                h2 { font-size: 1.3em; }
                h3 { font-size: 1.1em; }
                p {
                    margin: 12px 0;
                }
                ul, ol {
                    padding-left: 24px;
                }
                li {
                    margin: 4px 0;
                }
                table {
                    border-collapse: collapse;
                    width: 100%;
                    margin: 16px 0;
                }
                th, td {
                    border: 1px solid rgba(128, 128, 128, 0.3);
                    padding: 8px;
                    text-align: left;
                }
                th {
                    background: rgba(128, 128, 128, 0.1);
                }
                hr {
                    border: none;
                    border-top: 1px solid rgba(128, 128, 128, 0.3);
                    margin: 24px 0;
                }
            </style>
        </head>
        <body>
            \(content)
            <script>
                // Report height after content loads
                function reportHeight() {
                    const height = document.body.scrollHeight;
                    window.webkit.messageHandlers.heightHandler.postMessage(height);
                }
                window.onload = reportHeight;
                // Also report after images load
                document.querySelectorAll('img').forEach(img => {
                    img.onload = reportHeight;
                });
            </script>
        </body>
        </html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: HTMLContentView

        init(_ parent: HTMLContentView) {
            self.parent = parent
            super.init()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Add message handler for height updates
            webView.configuration.userContentController.add(self, name: "heightHandler")

            // Get content height
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, error in
                if let height = result as? CGFloat {
                    DispatchQueue.main.async {
                        self?.parent.dynamicHeight = max(height, 100)
                    }
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "heightHandler", let height = message.body as? CGFloat {
                DispatchQueue.main.async {
                    self.parent.dynamicHeight = max(height, 100)
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Open links in external browser
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

#Preview {
    ScrollView {
        HTMLContentView(
            html: """
            <h2>Sample Article</h2>
            <p>This is a <strong>sample</strong> article with <em>formatted</em> text.</p>
            <ul>
                <li>First item</li>
                <li>Second item</li>
            </ul>
            <blockquote>This is a quote from the article.</blockquote>
            <p>Here's some <code>inline code</code> and a link: <a href="https://example.com">Example</a></p>
            """,
            dynamicHeight: .constant(300)
        )
        .frame(height: 300)
        .padding()
    }
}
