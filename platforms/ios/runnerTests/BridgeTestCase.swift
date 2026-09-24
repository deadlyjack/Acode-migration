import XCTest
import WebKit

@MainActor
class BridgeTestCase: XCTestCase {
    override func setUp() async throws {
        let webView = try await appWebView()
        let marker = "iosConsentFixture"
        let scripts = webView.configuration.userContentController
        guard !scripts.userScripts.contains(where: { $0.source.contains(marker) }) else { return }
        // Unrelated integration tests must not depend on network consent forms.
        // Native AdMob actions are still exercised directly by AdsBridgeTests.
        scripts.addUserScript(WKUserScript(source: """
            Object.defineProperty(window,'admob',{configurable:true,set(value){
                value.privacy.gatherConsent=async function iosConsentFixture(){
                    return {consentStatus:'unknown',canRequestAds:false,privacyOptionsRequired:false};
                };
                Object.defineProperty(window,'admob',{configurable:true,writable:true,value});
            }});
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView.reload()
        try await Task.sleep(for: .milliseconds(200))
        _ = try await appWebView()
    }

    func appWebView() async throws -> WKWebView {
        for _ in 0..<100 {
            for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                for window in scene.windows {
                    if let webView = findWebView(window), webView.url?.scheme == "acode", !webView.isLoading,
                       (try? await webView.evaluateJavaScript("!!window.Bridge")) as? Bool == true { return webView }
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw NSError(domain: "AcodeTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "App WebView not mounted"])
    }

    func editorWebView() async throws -> WKWebView {
        let webView = try await appWebView()
        for _ in 0..<150 {
            if (try? await webView.evaluateJavaScript("!!window.acode && !!window.editorManager && !document.body.classList.contains('loading')")) as? Bool == true { return webView }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw NSError(domain: "AcodeTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Editor startup did not finish"])
    }

    private func findWebView(_ view: UIView) -> WKWebView? {
        if let webView = view as? WKWebView, webView.url?.scheme == "acode" { return webView }
        for child in view.subviews { if let found = findWebView(child) { return found } }
        return nil
    }
}
