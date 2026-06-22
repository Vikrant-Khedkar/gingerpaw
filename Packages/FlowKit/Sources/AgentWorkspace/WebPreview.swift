import AppKit
import SwiftUI
import WebKit

struct ClickEvent: Sendable {
    let tag: String
    let text: String
    let selector: String
}

/// Captures semantic clicks from the page and posts them to native.
private let clickCaptureJS = """
document.addEventListener('click', function(e) {
  try {
    var t = e.target;
    var text = (t.innerText || t.value || t.getAttribute('aria-label') || '').trim().slice(0, 80);
    var sel = t.tagName.toLowerCase()
      + (t.id ? '#' + t.id : '')
      + (typeof t.className === 'string' && t.className.trim() ? '.' + t.className.trim().split(/\\s+/).join('.') : '');
    window.webkit.messageHandlers.gpClick.postMessage({ tag: t.tagName, text: text, selector: sel });
  } catch (err) {}
}, true);
"""

private final class ClickRelay: NSObject, WKScriptMessageHandler {
    var onClick: ((ClickEvent) -> Void)?
    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "gpClick", let d = message.body as? [String: Any] else { return }
        onClick?(ClickEvent(tag: d["tag"] as? String ?? "",
                            text: d["text"] as? String ?? "",
                            selector: d["selector"] as? String ?? ""))
    }
}

/// Owns a persistent WKWebView so it survives view updates. Exposes load, reload, snapshot,
/// and a click callback the feedback recorder consumes.
@MainActor
final class WebPreviewController {
    let webView: WKWebView
    private let relay = ClickRelay()

    var onClick: ((ClickEvent) -> Void)? {
        get { relay.onClick }
        set { relay.onClick = newValue }
    }

    init() {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.addUserScript(WKUserScript(source: clickCaptureJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        cfg.userContentController.add(relay, name: "gpClick")
        webView = WKWebView(frame: .zero, configuration: cfg)
        webView.setValue(false, forKey: "drawsBackground")   // avoid white flash on dark UI
    }

    func load(_ url: URL) { webView.load(URLRequest(url: url)) }
    func reload() { webView.reload() }

    func snapshot() async -> NSImage? {
        await withCheckedContinuation { cont in
            let cfg = WKSnapshotConfiguration()
            webView.takeSnapshot(with: cfg) { image, _ in cont.resume(returning: image) }
        }
    }
}

struct WebPreviewView: NSViewRepresentable {
    let controller: WebPreviewController
    func makeNSView(context: Context) -> WKWebView { controller.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
