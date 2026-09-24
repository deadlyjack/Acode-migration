import XCTest
@testable import runner

final class RewardPassTests: XCTestCase {
    private let store = SecretStore(namespace: "ios-test.rewards." + UUID().uuidString)
    private let hour: Int64 = 3_600_000

    override func tearDownWithError() throws { try store.clear() }

    func testQuickPassPersistsAndDailyLimitResetsAtLocalMidnight() throws {
        var date = Calendar.current.startOfDay(for: Date()).addingTimeInterval(23 * 3600 + 1800)
        let rewards = RewardPassManager(store: store, now: { date })
        let initial = try status(rewards.getRewardStatus())
        XCTAssertEqual(initial["remainingRedemptions"] as? Int, 3)
        XCTAssertEqual(initial["isActive"] as? Bool, false)
        XCTAssertThrowsError(try rewards.redeemReward("invalid")) { XCTAssertEqual($0.localizedDescription, "Unknown reward offer.") }
        let first = try status(rewards.redeemReward("quick"))
        XCTAssertEqual(first["grantedDurationMs"] as? Int64, hour)
        XCTAssertEqual(first["appliedDurationMs"] as? Int64, hour)
        XCTAssertEqual(first["offerId"] as? String, "quick")
        XCTAssertEqual(first["isActive"] as? Bool, true)
        let reopened = RewardPassManager(store: store, now: { date })
        let persisted = try status(reopened.getRewardStatus())
        XCTAssertEqual(first["adFreeUntil"] as? Int64, persisted["adFreeUntil"] as? Int64)
        _ = try rewards.redeemReward("quick")
        let third = try status(rewards.redeemReward("quick"))
        XCTAssertEqual(third["remainingMs"] as? Int64, 3 * hour)
        XCTAssertEqual(third["remainingRedemptions"] as? Int, 0)
        XCTAssertEqual(third["canRedeem"] as? Bool, false)
        XCTAssertThrowsError(try rewards.redeemReward("quick")) {
            XCTAssertEqual($0.localizedDescription, "Daily limit reached. You can redeem up to 3 rewards per day.")
        }
        date = date.addingTimeInterval(1800)
        let nextDay = try status(reopened.getRewardStatus())
        XCTAssertEqual(nextDay["remainingRedemptions"] as? Int, 3)
        XCTAssertEqual(nextDay["remainingMs"] as? Int64, 9_000_000)
        XCTAssertEqual(nextDay["canRedeem"] as? Bool, true)
    }

    func testFocusOfferRangeAndTenHourCap() throws {
        let date = Date()
        for hours in 4...6 {
            try store.clear()
            let rewards = RewardPassManager(store: store, now: { date }, focusHours: { hours })
            let first = try status(rewards.redeemReward("focus"))
            XCTAssertEqual(first["grantedDurationMs"] as? Int64, Int64(hours) * hour)
        }
        let rewards = RewardPassManager(store: store, now: { date }, focusHours: { 6 })
        let capped = try status(rewards.redeemReward("focus"))
        XCTAssertEqual(capped["grantedDurationMs"] as? Int64, 6 * hour)
        XCTAssertEqual(capped["appliedDurationMs"] as? Int64, 4 * hour)
        XCTAssertEqual(capped["remainingMs"] as? Int64, 10 * hour)
        XCTAssertEqual(capped["remainingRedemptions"] as? Int, 1)
        XCTAssertEqual(capped["canRedeem"] as? Bool, false)
        XCTAssertThrowsError(try rewards.redeemReward("quick")) {
            XCTAssertEqual($0.localizedDescription, "You already have the maximum 10 hours of ad-free time active.")
        }
    }

    func testExpiryNoticeIsConsumedOnceAndMalformedStateRecovers() throws {
        var date = Date()
        let rewards = RewardPassManager(store: store, now: { date })
        try store.set("reward_state", value: "malformed")
        let grant = try status(rewards.redeemReward("quick"))
        date = date.addingTimeInterval(3600)
        let expired = try status(rewards.getRewardStatus())
        XCTAssertEqual(expired["isActive"] as? Bool, false)
        XCTAssertEqual(expired["adFreeUntil"] as? Int64, 0)
        XCTAssertEqual(expired["remainingMs"] as? Int64, 0)
        XCTAssertEqual(expired["hasPendingExpiryNotice"] as? Bool, true)
        XCTAssertEqual(expired["expiryNoticePendingUntil"] as? Int64, grant["adFreeUntil"] as? Int64)
        let reopened = RewardPassManager(store: store, now: { date })
        let consumed = try status(reopened.getRewardStatus())
        XCTAssertEqual(consumed["hasPendingExpiryNotice"] as? Bool, false)
        XCTAssertEqual(consumed["lastExpiredRewardUntil"] as? Int64, grant["adFreeUntil"] as? Int64)
        let renewed = try status(reopened.redeemReward("quick"))
        XCTAssertEqual(renewed["lastExpiredRewardUntil"] as? Int64, 0)
        XCTAssertEqual(renewed["expiryNoticePendingUntil"] as? Int64, 0)
        try store.set("reward_state", value: "{\"redemptionsToday\":2}")
        XCTAssertEqual(try status(rewards.getRewardStatus())["remainingRedemptions"] as? Int, 1)
    }

    private func status(_ value: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any])
    }
}

@MainActor
final class RewardBridgeTests: BridgeTestCase {
    func testPublicStatusAPIAndUnknownOfferRejection() async throws {
        let webView = try await appWebView()
        let result = try await webView.callAsyncJavaScript("""
            const raw=await new Promise((resolve,reject)=>system.getRewardStatus(resolve,reject));
            if(typeof raw!=='string')throw Error('Changed reward response type');
            const status=JSON.parse(raw);
            if(status.maxRedemptionsPerDay!==3||status.maxActivePassMs!==36000000)throw Error('Changed reward limits');
            if(typeof status.hasPendingExpiryNotice!=='boolean')throw Error('Missing expiry policy');
            try{await new Promise((resolve,reject)=>system.redeemReward('invalid',resolve,reject));return false;}
            catch(error){return typeof error==='string'&&!error.includes('unavailable on iOS');}
            """, arguments: [:], in: nil, contentWorld: .page) as? Bool
        XCTAssertEqual(result, true)
    }
}
