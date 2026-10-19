import XCTest
@testable import GenStationCore

/// Fix B (Stage 3 whole-branch triage, item B). `isAIMLModelCacheStale`
/// (`GenStation/App/GenStationApp.swift`) used to run entirely inside `SettingsState`, where the app
/// target's lack of any test harness made it permanently unverifiable. `AIMLModelCacheStaleness.isStale`
/// is the extracted, pure decision — every input the property used to read off `self`/`UserDefaults`/
/// `Date()` is now an explicit argument, so it can be pinned here.
final class AIMLModelCacheStalenessTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let expiryHours: Double = 24

    private func isStale(servedModelsEmpty: Bool = false,
                          idsEmpty: Bool = false,
                          cachedAt: Date?) -> Bool {
        AIMLModelCacheStaleness.isStale(servedModelsEmpty: servedModelsEmpty,
                                         idsEmpty: idsEmpty,
                                         cachedAt: cachedAt,
                                         now: now,
                                         expiryHours: expiryHours)
    }

    // MARK: No timestamp

    func testNoTimestampIsStale() {
        XCTAssertTrue(isStale(cachedAt: nil))
    }

    // MARK: Expiry boundary — exactly at, just inside, just outside

    func testExactlyAtTheExpiryThresholdIsNotStale() {
        let cachedAt = now.addingTimeInterval(-expiryHours * 3600)
        XCTAssertFalse(isStale(cachedAt: cachedAt), "> is stale, not >=; equal to the threshold is not yet stale")
    }

    func testJustInsideTheExpiryThresholdIsNotStale() {
        let cachedAt = now.addingTimeInterval(-(expiryHours * 3600 - 1))
        XCTAssertFalse(isStale(cachedAt: cachedAt))
    }

    func testJustOutsideTheExpiryThresholdIsStale() {
        let cachedAt = now.addingTimeInterval(-(expiryHours * 3600 + 1))
        XCTAssertTrue(isStale(cachedAt: cachedAt))
    }

    // MARK: The empty-served-but-ids-present upgrade case

    func testEmptyServedModelsWithNonEmptyIdsIsStaleRegardlessOfTimestamp() {
        // A pre-Stage-3 cache: ids exist, served metadata does not. Stale even with a fresh
        // timestamp, because the upgrade check is unconditional — it must not wait for expiry.
        XCTAssertTrue(isStale(servedModelsEmpty: true, idsEmpty: false, cachedAt: now))
    }

    func testEmptyServedModelsWithEmptyIdsIsNotForcedStaleByTheUpgradeRule() {
        // Both empty (nothing ever cached, or a clean cold start) is not the upgrade case — it falls
        // through to the ordinary timestamp check, same as any other fresh cache.
        XCTAssertFalse(isStale(servedModelsEmpty: true, idsEmpty: true, cachedAt: now))
    }

    func testNonEmptyServedModelsIsNotForcedStaleByTheUpgradeRuleEvenWithEmptyIds() {
        // The upgrade rule only fires when served IS empty; served metadata present means this was
        // written by the current cache shape, whatever idsEmpty says.
        XCTAssertFalse(isStale(servedModelsEmpty: false, idsEmpty: true, cachedAt: now))
    }

    // MARK: Other edges

    func testAFutureTimestampIsNotStale() {
        // Clock skew / a cache written "in the future" relative to `now`: hoursSinceCache is
        // negative, which is never > expiryHours.
        let cachedAt = now.addingTimeInterval(3600)
        XCTAssertFalse(isStale(cachedAt: cachedAt))
    }

    func testTheUpgradeRuleOutranksAFreshTimestamp() {
        // Belt-and-suspenders on the ordering the property's guard implies: the upgrade check must
        // run (and return true) before the timestamp is even consulted.
        XCTAssertTrue(isStale(servedModelsEmpty: true, idsEmpty: false, cachedAt: now))
    }
}
