import CryptoKit
import XCTest
@testable import runner

final class AuthenticationTests: XCTestCase {
    private var auth: AppAuthentication!

    override func setUpWithError() throws { auth = AppAuthentication(namespace: "test-auth-" + UUID().uuidString) }
    override func tearDownWithError() throws { try auth.secrets.clear() }

    @MainActor
    func testAuthenticationLinksDoNotReachPluginIntentObservers() {
        let links = IncomingLinks()
        var received: URL?
        links.authenticationHandler = { received = $0 }
        let leaked = expectation(description: "Authentication URL reached plugin observers")
        leaked.isInverted = true
        let observer = NotificationCenter.default.addObserver(forName: .acodeDeepLink, object: nil, queue: nil) { _ in leaked.fulfill() }
        defer { NotificationCenter.default.removeObserver(observer) }
        let url = URL(string: "acode://auth/callback?code=fixture&state=fixture")!
        links.receive(url)
        XCTAssertEqual(received, url)
        wait(for: [leaked], timeout: 0.01)
    }

    func testLoginChallengeAndOneTimeExchangeMatchTheExistingServerProtocol() throws {
        let url = try auth.begin(baseURL: "https://acode.app", version: 1011)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
        XCTAssertEqual(url.path, "/login")
        XCTAssertEqual(values["authFlow"], "app-code")
        XCTAssertEqual(values["redirect"], "app")
        XCTAssertEqual(values["appVersionCode"], "1011")
        XCTAssertEqual(values["state"]?.count, 48)
        let callback = URL(string: "acode://auth/callback?state=\(values["state"]!)&code=test-code")!
        let request = try auth.consume(callback)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String])
        XCTAssertEqual(request.url?.absoluteString, "https://acode.app/api/user/app-token/exchange")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(payload["code"], "test-code")
        XCTAssertEqual(payload["state"], values["state"])
        XCTAssertEqual(payload["verifier"]?.count, 64)
        let digest = SHA256.hash(data: Data(payload["verifier"]!.utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(values["challenge"], digest)
        XCTAssertThrowsError(try auth.consume(callback))
        XCTAssertEqual(try auth.secrets.get("pending_login"), "")
    }

    func testRejectsForgedCallbacksUntrustedOriginsAndInvalidCookieTokens() throws {
        for value in ["http://acode.app", "https://acode.app.evil.test", "https://acode.app:8443", "https://user@acode.app", "https://acode.app/path"] {
            XCTAssertThrowsError(try auth.begin(baseURL: value, version: 1))
        }
        let url = try auth.begin(baseURL: "https://acode.app", version: 1)
        let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
        for value in ["acode://auth/callback?state=wrong&code=test", "acode://auth/callback?state=\(state)&code=", "acode://plugin/callback?state=\(state)&code=test", "acode://auth/callback?state=\(state)&state=\(state)&code=test"] {
            XCTAssertThrowsError(try auth.consume(URL(string: value)!))
        }
        for token in ["", "x;other=y", "x\r\ny", "unicode✓", "a b"] { XCTAssertThrowsError(try auth.save(token)) }
        try auth.save("fixture.token-123_value")
        XCTAssertEqual(try auth.secrets.get("auth_token"), "fixture.token-123_value")
        try auth.logout()
        XCTAssertEqual(try auth.secrets.get("auth_token"), "")
        XCTAssertEqual(try auth.secrets.get("pending_login"), "")
    }
}
