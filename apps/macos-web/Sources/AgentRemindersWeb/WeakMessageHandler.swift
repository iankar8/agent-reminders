import WebKit

/// Retain-cycle breaker. `WKUserContentController` strongly holds its message
/// handlers; if we add the Bridge directly it lives forever. Pass this weak
/// wrapper instead and the Bridge can deallocate normally.
final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(ucc, didReceive: message)
    }
}
