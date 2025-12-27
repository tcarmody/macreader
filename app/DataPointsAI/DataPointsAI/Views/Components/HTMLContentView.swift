import SwiftUI
import WebKit

/// WKWebView subclass that passes scroll events to parent
class NonScrollingWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        // Pass scroll events to the next responder (parent ScrollView)
        nextResponder?.scrollWheel(with: event)
    }
}

/// A SwiftUI view that renders HTML content using WKWebView
struct HTMLContentView: NSViewRepresentable {
    let html: String
    @Binding var dynamicHeight: CGFloat
    var fontSize: CGFloat = 14
    var lineHeight: CGFloat = 1.6
    var fontFamily: String = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif"
    var theme: ArticleTheme = .auto

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "heightHandler")

        let webView = NonScrollingWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let styledHTML = wrapHTMLWithStyles(html)
        webView.loadHTMLString(styledHTML, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "heightHandler")
    }

    private func wrapHTMLWithStyles(_ content: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                \(theme.cssStyles)
                body {
                    font-family: \(fontFamily);
                    font-size: \(Int(fontSize))px;
                    line-height: \(lineHeight);
                    color: var(--text-color);
                    background: var(--bg-color);
                    margin: 0;
                    padding: 12px;
                    word-wrap: break-word;
                    overflow-wrap: break-word;
                    overflow: hidden;
                    border-radius: 8px;
                }
                a {
                    color: var(--link-color);
                }
                img {
                    max-width: 100%;
                    height: auto;
                    border-radius: 4px;
                }
                pre, code {
                    background: var(--code-bg);
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
                    border-left: 3px solid var(--border-color);
                    margin: 16px 0;
                    padding-left: 16px;
                    color: var(--blockquote-color);
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
                    border: 1px solid var(--border-color);
                    padding: 8px;
                    text-align: left;
                }
                th {
                    background: var(--code-bg);
                }
                hr {
                    border: none;
                    border-top: 1px solid var(--border-color);
                    margin: 24px 0;
                }
            </style>
        </head>
        <body>
            \(content)
            <script>
                // Report height after content loads
                function reportHeight() {
                    // Use a small delay to ensure rendering is complete
                    setTimeout(function() {
                        const height = Math.max(
                            document.body.scrollHeight,
                            document.body.offsetHeight,
                            document.documentElement.scrollHeight,
                            document.documentElement.offsetHeight
                        );
                        window.webkit.messageHandlers.heightHandler.postMessage(height);
                    }, 50);
                }

                // Initial report
                window.onload = reportHeight;

                // Report after images load
                document.querySelectorAll('img').forEach(img => {
                    img.onload = reportHeight;
                });

                // Use ResizeObserver for dynamic content changes
                if (typeof ResizeObserver !== 'undefined') {
                    const resizeObserver = new ResizeObserver(reportHeight);
                    resizeObserver.observe(document.body);
                }

                // Fallback: report height periodically for first second
                let checks = 0;
                const interval = setInterval(function() {
                    reportHeight();
                    checks++;
                    if (checks >= 5) clearInterval(interval);
                }, 200);
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
            // Get content height after page loads with multiple attempts
            func checkHeight(attempt: Int = 0) {
                let js = """
                    Math.max(
                        document.body.scrollHeight,
                        document.body.offsetHeight,
                        document.documentElement.scrollHeight,
                        document.documentElement.offsetHeight
                    )
                """
                webView.evaluateJavaScript(js) { [weak self] result, error in
                    if let height = result as? CGFloat, height > 0 {
                        DispatchQueue.main.async {
                            self?.parent.dynamicHeight = height
                        }
                    } else if attempt < 3 {
                        // Retry after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            checkHeight(attempt: attempt + 1)
                        }
                    }
                }
            }
            checkHeight()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "heightHandler", let height = message.body as? CGFloat {
                DispatchQueue.main.async {
                    self.parent.dynamicHeight = height
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
