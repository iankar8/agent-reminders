import WebKit

/// Owns the WKWebView: configures the bridge bootstrap, makes the background
/// transparent so the NSVisualEffectView shows through, loads the bundled HTML,
/// and pushes Swift→JS events.
final class WebPanelController: NSObject, WKNavigationDelegate {
    let webView: WKWebView

    init(bridge: Bridge) {
        let config = WKWebViewConfiguration()

        // Bootstrap the JS side of the bridge before page JS runs.
        let bootstrap = """
        window.__native = {
          _h: {},
          on: function(ev, fn){ this._h[ev] = fn; },
          dispatch: function(ev, json){ var f = this._h[ev]; if (f) f(JSON.parse(json)); },
          call: function(action, payload){
            window.webkit.messageHandlers.bridge.postMessage({ action: action, payload: payload || {} });
          }
        };
        """
        config.userContentController.addUserScript(
            WKUserScript(source: bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        config.userContentController.add(WeakMessageHandler(delegate: bridge), name: "bridge")

        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self

        // Transparency — both steps required (private but stable since 10.12).
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.0, *) { webView.underPageBackgroundColor = .clear }

        load()
    }

    private func load() {
        guard let url = Bundle.module.url(forResource: "panel", withExtension: "html") else { return }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    /// Swift → JS event push (live store updates / poll reconciliation).
    @MainActor func send(event: String, json: String) {
        let js = "window.__native.dispatch('\(event)', \(Self.jsStringLiteral(json)));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Encode an arbitrary string as a safe JS string literal (it carries JSON).
    private static func jsStringLiteral(_ s: String) -> String {
        if let data = try? JSONEncoder().encode(s), let lit = String(data: data, encoding: .utf8) {
            return lit
        }
        return "\"\""
    }
}
