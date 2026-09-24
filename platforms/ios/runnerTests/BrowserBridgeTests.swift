import SafariServices
import XCTest
@testable import runner

@MainActor
final class BrowserBridgeTests: BridgeTestCase {
    func testCustomTabsPresentSafariAndRejectInvalidSchemes() async throws {
        let webView = try await appWebView()
        let invalid = try await webView.callAsyncJavaScript("""
            for(const url of ['javascript:alert(1)', 'file:///etc/passwd', 'not a URL']) {
                let rejected=false;
                try { await new Promise((resolve,reject)=>CustomTabs.open(url,{},resolve,reject)); }
                catch { rejected=true; }
                if(!rejected) return false;
            }
            return true;
            """, arguments: [:], in: nil, contentWorld: .page) as? Bool
        XCTAssertEqual(invalid, true)
        var responder: UIResponder? = webView
        while responder != nil, !(responder is WebViewController) { responder = responder?.next }
        let controller = try XCTUnwrap(responder as? WebViewController)
        XCTAssertNil(controller.presentedViewController, "Presentation already active: \(String(describing: controller.presentedViewController))")
        let fixture = try HTTPFixture()
        try await fixture.start()
        defer { fixture.stop() }
        _ = try await webView.callAsyncJavaScript("await new Promise((resolve,reject)=>CustomTabs.open(url,{toolbarColor:'#123456'},resolve,reject));", arguments: ["url": fixture.origin], in: nil, contentWorld: .page)
        let browser = try XCTUnwrap(controller.presentedViewController as? SFSafariViewController)
        if #unavailable(iOS 26) { XCTAssertEqual(browser.preferredBarTintColor, UIColor(hexString: "#123456")) }
        XCTAssertEqual(browser.dismissButtonStyle, .close)
        XCTAssertEqual(webView.url?.absoluteString, "acode://localhost/")
        await withCheckedContinuation { continuation in browser.dismiss(animated: false) { continuation.resume() } }
    }
}
