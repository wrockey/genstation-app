// One healer, not four (design § 3.7). The four sites this replaces disagreed about when a user's
// model selection may be silently rewritten, and the collapse changes what is in the offered list —
// which is what made bug 5 (design § 5) more likely to fire.
//
// The policy is a pure function so it can be tested. Its call sites are app-layer and are verified
// by the compile gates plus the live-test checklist.

import XCTest
@testable import GenStationCore

final class SelectionHealerTests: XCTestCase {

    private func aliasPair() throws -> (alias: String, canonical: String) {
        let group = try XCTUnwrap(AliasGroups.groups.first { $0.count > 1 })
        let canonical = try XCTUnwrap(Catalog.canonicalID(for: group[0]))
        let alias = try XCTUnwrap(group.first { $0 != canonical })
        return (alias, canonical)
    }

    func testAnEmptySelectionTakesTheFirstOfferedModel() {
        XCTAssertEqual(SelectionHealer.heal(selected: "", offered: ["b", "a"],
                                            preferring: [], hasCustomPayload: false), "b")
    }

    /// This is the launch case. `loadCachedAIMLModels()` runs from `AppState.init`, long before
    /// `ConfigurationSection` has populated `configurationAvailableModels`, so `offered` is empty.
    /// An empty offered list must never be a reason to clear or change anything.
    func testAnEmptySelectionWithNothingOfferedIsLeftAlone() {
        XCTAssertNil(SelectionHealer.heal(selected: "", offered: [],
                                          preferring: [], hasCustomPayload: false))
    }

    func testAnAliasSpellingIsCanonicalizedEvenWithNothingOffered() throws {
        let pair = try aliasPair()
        XCTAssertEqual(SelectionHealer.heal(selected: pair.alias, offered: [],
                                            preferring: [], hasCustomPayload: false),
                       pair.canonical)
    }

    func testACanonicalIdAbsentFromANonEmptyOfferedListIsReplaced() throws {
        // C1. A resolvable selection that the current offered list does not include is a genuine
        // mode mismatch — e.g. an image model surviving a switch into video mode — not a legitimate
        // hand pick like the unresolvable-but-offered case below. Leaving it alone (the bug this
        // guards) let `ContentView+Generation.swift` post a wrong-task request against a model with
        // no `pollingEndpoint`, since it branches on `isVideoMode`, not on `model.isVideo`.
        let canonical = try XCTUnwrap(Catalog.all.first).id
        XCTAssertEqual(SelectionHealer.heal(selected: canonical, offered: ["something-else"],
                                            preferring: [], hasCustomPayload: false),
                       "something-else")
    }

    func testACanonicalIdIsLeftAloneWhenNothingIsOffered() throws {
        // The empty-offered case (launch, before any picker exists) must still never be a reason to
        // reassign — only a non-empty offered list is an authority on what's usable right now.
        let canonical = try XCTUnwrap(Catalog.all.first).id
        XCTAssertNil(SelectionHealer.heal(selected: canonical, offered: [],
                                          preferring: [], hasCustomPayload: false))
    }

    func testACanonicalIdThatIsOfferedIsLeftAlone() throws {
        let canonical = try XCTUnwrap(Catalog.all.first).id
        XCTAssertNil(SelectionHealer.heal(selected: canonical, offered: [canonical, "something-else"],
                                          preferring: [], hasCustomPayload: false))
    }

    func testACustomPayloadBlocksReplacementEvenWhenTheSelectionIsAbsentFromOffered() throws {
        let canonical = try XCTUnwrap(Catalog.all.first).id
        XCTAssertNil(SelectionHealer.heal(selected: canonical, offered: ["something-else"],
                                          preferring: [], hasCustomPayload: true))
    }

    func testAnAliasThatIsOfferedUnderItsCanonicalSpellingCanonicalizesRatherThanBeingReplaced() throws {
        let pair = try aliasPair()
        XCTAssertEqual(SelectionHealer.heal(selected: pair.alias, offered: [pair.canonical, "something-else"],
                                            preferring: [], hasCustomPayload: false),
                       pair.canonical)
    }

    func testAnUnresolvableIdThatIsOfferedIsLeftAlone() {
        // Advanced mode: a raw API id with no catalog row is a legitimate selection.
        XCTAssertNil(Catalog.canonicalID(for: "alibaba/qwen-image-3"),
                     "this id must stay unregistered, or the test proves nothing")
        XCTAssertNil(SelectionHealer.heal(selected: "alibaba/qwen-image-3",
                                          offered: ["alibaba/qwen-image-3", "x"],
                                          preferring: [], hasCustomPayload: false))
    }

    func testAnUnresolvableIdThatIsNotOfferedIsReplaced() {
        XCTAssertEqual(SelectionHealer.heal(selected: "alibaba/qwen-image-3", offered: ["x", "y"],
                                            preferring: [], hasCustomPayload: false), "x")
    }

    /// Task 5's guarantee, restated as a property of the one healer rather than of one call site:
    /// an automatic reassignment never discards a user-edited payload. This is what makes it safe
    /// to delete Task 5's `isAutoSelectingAIMLModel` flag in Step 7.
    func testNothingIsEverReassignedWhileAHandEditedPayloadExists() throws {
        XCTAssertNil(SelectionHealer.heal(selected: "alibaba/qwen-image-3", offered: ["x", "y"],
                                          preferring: [], hasCustomPayload: true))
        XCTAssertNil(SelectionHealer.heal(selected: try aliasPair().alias, offered: [],
                                          preferring: [], hasCustomPayload: true))
        XCTAssertNil(SelectionHealer.heal(selected: "", offered: ["x"],
                                          preferring: [], hasCustomPayload: true))
    }

    func testThePreferenceListIsConsultedOnlyWhenAReplacementIsNeeded() {
        // Gemini's ladder. It picks among the offered models when the selection is unusable, and
        // it does NOT override a usable one — which is what GenStationApp.swift:525-532 does today.
        let offered = ["gemini-2.5-flash-image", "gemini-3-pro-image-preview"]
        let preferred = ["gemini-3-pro-image-preview", "gemini-2.5-flash-image"]
        XCTAssertEqual(SelectionHealer.heal(selected: "", offered: offered,
                                            preferring: preferred, hasCustomPayload: false),
                       "gemini-3-pro-image-preview")
        XCTAssertNil(SelectionHealer.heal(selected: "gemini-2.5-flash-image", offered: offered,
                                          preferring: preferred, hasCustomPayload: false))
    }

    func testAPreferenceThatIsNotOfferedIsSkipped() {
        XCTAssertEqual(SelectionHealer.heal(selected: "", offered: ["b"],
                                            preferring: ["a", "b"], hasCustomPayload: false), "b")
    }
}
