// The "is our cached AI/ML model list stale" rule, extracted so it can be tested at all.
//
// It used to live entirely inside `SettingsState.isAIMLModelCacheStale`
// (`GenStation/App/GenStationApp.swift`), which reads `UserDefaults` and `Date()` directly — and
// the app target has no test harness, so every rule that lived there was permanently unverifiable.
// This is real logic (an empty-served-but-non-empty-ids upgrade check, a missing-timestamp check,
// and an expiry-hours comparison), not glue, so it belongs where it can be pinned. `isStale(...)` is
// the decision, taking its inputs explicitly — including "now" — so a test can hold time still
// instead of racing `Date()`. `SettingsState.isAIMLModelCacheStale` becomes a thin call that reads
// `UserDefaults`/`Date()` and passes them in.

import Foundation

public enum AIMLModelCacheStaleness {

    /// - Parameters:
    ///   - servedModelsEmpty: `true` when the cached per-model metadata (`ServedModel` rows) is
    ///     empty. Checked against `idsEmpty` below, not on its own — see the first rule.
    ///   - idsEmpty: `true` when the cached flat id list is empty. A cache written before this
    ///     release holds ids and nothing else; `servedModelsEmpty && !idsEmpty` is exactly that
    ///     shape, and reporting it stale routes it through the refresh path that already exists
    ///     rather than leaving the picker with ids it cannot classify, name or order.
    ///   - cachedAt: when the cache was last written, or `nil` if it never has been.
    ///   - now: the caller's current time. Always inject this — a decision that calls `Date()`
    ///     internally can only ever be checked at one instant and proves nothing under test.
    ///   - expiryHours: how many hours old a cache may be before it counts as stale.
    public static func isStale(servedModelsEmpty: Bool,
                                idsEmpty: Bool,
                                cachedAt: Date?,
                                now: Date,
                                expiryHours: Double) -> Bool {
        // Pre-Stage-3 cache: ids exist but the per-model metadata that seeds classification, naming
        // and ordering does not. Stale regardless of the timestamp below.
        if servedModelsEmpty && !idsEmpty { return true }

        guard let cachedAt else { return true }  // No timestamp = never cached.

        let hoursSinceCache = now.timeIntervalSince(cachedAt) / 3600
        return hoursSinceCache > expiryHours
    }
}
