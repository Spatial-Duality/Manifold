import SwiftUI
import WebKit
import ManifoldKit

struct HTMLEmailView: NSViewRepresentable {
    let html: String
    let attachments: [MIMEParser.AttachmentPart]

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let resolved = resolveCIDReferences(in: html)
        webView.loadHTMLString(wrapInViewport(resolved), baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Replace cid: references with base64 data: URIs.
    private func resolveCIDReferences(in html: String) -> String {
        var result = html
        for attachment in attachments {
            guard let contentID = attachment.contentID else { continue }
            // Strip angle brackets from Content-ID
            let cid = contentID
                .trimmingCharacters(in: .whitespaces)
                .replacing("<", with: "")
                .replacing(">", with: "")
            guard !cid.isEmpty else { continue }

            let base64 = attachment.data.base64EncodedString()
            let dataURI = "data:\(attachment.mimeType);base64,\(base64)"
            result = result.replacing("cid:\(cid)", with: dataURI)
        }
        return result
    }

    /// Wrap HTML in a viewport meta tag for proper scaling.
    private func wrapInViewport(_ html: String) -> String {
        if html.lowercased().contains("<html") { return html }
        return """
        <!DOCTYPE html>
        <html><head>
        <meta charset="utf-8">
        <style>
            body { font-family: -apple-system, system-ui; font-size: 14px; padding: 16px; margin: 0; color: #1d1d1f; }
            img { max-width: 100%; height: auto; }
            a { color: #0066cc; }
        </style>
        </head><body>\(html)</body></html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        // Block navigation to external URLs
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                return .cancel
            }
            return .allow
        }
    }
}
