// Spec § 3.6 invariant 8: a model's `task` agrees with the classification the live `/models`
// endpoint declares for it.
//
// This is the only Stage 3 invariant that checks the app against an EXTERNAL source of truth. Every
// other one is internal consistency. It exists because the app classifies models with a 35-token
// substring heuristic over model ids (`ConfigurationSection.filterModelsLocally()`) while the API
// states the answer outright.
//
// THE `type` FIELD IS AN ENDPOINT FAMILY, NOT A TASK. It reads `internal/video-generations/submit`,
// `openai/image-generations`, `openai/chat-completions`, … The classification is therefore THREE-WAY:
//
//     video   internal/video-generations/submit                     210 of 902 entries
//     image   openai/image-generations, openai/image-editing        127 + 5 = 132 entries
//     other   chat, responses, messages, batches, tts, stt,         560 entries
//             embeddings, audio, ocr
//
// The 560 are not "unclassifiable". They are not generation models, and the pickers must exclude
// them. `AIMLEndpoints.wireTask(forEndpointFamilies:)` owns that decision; this file asserts it.
//
// WHY IT IS ASSERTED AGAINST `ModelRegistry` AND NOT `Catalog`:
// `Catalog` does not exist until Task 9. Task 8 transcribes the registry's `isVideo:` into
// `CatalogModel.task` verbatim, and Task 9's Phase-A equivalence gate proves catalog == registry for
// all 209 ids. Registry == wire (here) composed with catalog == registry (Task 9) is exactly
// invariant 8. That is not a weaker statement, only an earlier one.
//
// TASK 18, WHEN YOU DELETE `ModelRegistry.swift`, THIS IS YOUR EDIT — and it is the whole edit:
//   replace the body of `registeredTasks()` with
//       var out: [String: CreateTask] = [:]
//       for model in Catalog.all {
//           out[model.id] = model.task
//           for alias in model.aliases { out[alias] = model.task }
//       }
//       return out
//   and delete `testTheRegistryParseIsHonest`. No assertion in the two invariant tests changes.

import XCTest
@testable import GenStationCore

final class AIMLTypeAgreementTests: XCTestCase {

    // MARK: - Measured constants

    /// Registered spellings the captured response still serves. Task 22 deleted the 8 that were
    /// registered but unserved (`AliasGroups.swift`, `Catalog/Models/`), so every one of the 201
    /// spellings left in `Catalog.all` is now served. Task 5's Nano Banana 2 intake (2026-08-11)
    /// added 3 more spellings (google/gemini-3.1-flash-image-preview, its alias nano-banana-2, and
    /// google/gemini-3-1-flash-lite-image) and the captured /models response serves all three under
    /// `openai/image-generations`, so the served count rises with the registered count. Task 6's
    /// Seedream 5.0 Pro + FLUX.2 Max intake (2026-08-11) added 3 more (bytedance/seedream-5-0-pro,
    /// its alias bytedance/dola-seedream-5-0-pro, and blackforestlabs/flux-2-max) — all three are
    /// also served under `openai/image-generations` (each as its own top-level entry, not aliased to
    /// one another in the captured response).
    private static let registeredSpellingsServed = 208

    /// Empty after Task 22: the 8 formerly-unserved spellings are no longer registered at all —
    /// they were removed, not just left unserved — so nothing in `Catalog.all` can disagree with
    /// the live endpoint by being unserved. Still named rather than a bare count, so a future
    /// deletion that reintroduces an unserved spelling shows up here by name.
    private static let registeredSpellingsNotServed: [String] = []

    // MARK: - The registry side

    /// Every registered spelling -> the task its `reg()` group declares.
    ///
    /// Scoped to `.aimlapi`: `Catalog.all` now also carries `Grok.swift`'s direct-xAI rows
    /// (`grok-imagine-image`, `grok-imagine-image-quality`), which the AI/ML registry never listed
    /// and the AI/ML `/models` wire response never serves. Including them here would make those two
    /// ids look "unserved" by an endpoint they were never routed through, corrupting Task 22's
    /// delete list below. The brief's snippet at the top of this file predates that addition; this
    /// filter is the one-line fix `git grep`-confirmed necessary before trusting it.
    private static func registeredTasks() throws -> [String: CreateTask] {
        var out: [String: CreateTask] = [:]
        for model in Catalog.all where model.provider == .aimlapi {
            out[model.id] = model.task
            for alias in model.aliases { out[alias] = model.task }
        }
        return out
    }

    // MARK: - The tripwire

    /// A `type` value the classifier has never seen is a NEW ENDPOINT FAMILY. Without this, it would
    /// fall through `wireTask(forEndpointFamilies:)` to `.other` and its models would silently
    /// disappear from every picker — the exact failure mode the endpoint-family design is meant to
    /// make impossible.
    ///
    /// The known-value set is `AIMLEndpoints.knownEndpointFamilies`, a named production constant, so
    /// there is one place to triage a new family and no literal list scattered through the tests.
    func testEveryWireTypeIsAKnownEndpointFamily() throws {
        var unknown: Set<String> = []
        var histogram: [String: Int] = [:]
        for entry in try AIMLModelsFixture.rawEntries() {
            guard let type = entry["type"] as? String else {
                return XCTFail("entry \(entry["id"] ?? "?") carries no `type`")
            }
            histogram[type, default: 0] += 1
            if !AIMLEndpoints.knownEndpointFamilies.contains(type) { unknown.insert(type) }
        }
        XCTAssertEqual(
            unknown.sorted(), [],
            "the /models response now serves endpoint families this classifier does not know: "
            + "\(unknown.sorted()). Add each one to AIMLEndpoints.videoEndpointFamilies, "
            + ".imageEndpointFamilies or .nonGenerationEndpointFamilies deliberately — do not widen "
            + "the match into a substring test, which is the mistake this field replaced.")

        // The observed distribution, so a family that stops being served is also visible.
        XCTAssertEqual(histogram.values.reduce(0, +), 902)
        XCTAssertEqual(histogram["internal/video-generations/submit"], 210)
        XCTAssertEqual(histogram["openai/image-generations"], 127)
        XCTAssertEqual(histogram["openai/image-editing"], 5)
        XCTAssertEqual(histogram["openai/chat-completions"], 339)
        XCTAssertEqual(histogram.count, 14, "distinct endpoint families: \(histogram.keys.sorted())")
    }

    /// The three-way split over entries, stated as a measurement. `other` is 560 — the number that
    /// makes "exclude, don't tolerate" a real design decision rather than an afterthought.
    func testTheThreeWayClassificationCoversEveryEntry() throws {
        var counts: [AIMLEndpoints.WireTask: Int] = [:]
        for entry in try AIMLModelsFixture.rawEntries() {
            let type = (entry["type"] as? String) ?? ""
            counts[AIMLEndpoints.wireTask(forEndpointFamilies: [type]), default: 0] += 1
        }
        XCTAssertEqual(counts[.video], 210)
        XCTAssertEqual(counts[.image], 132)
        XCTAssertEqual(counts[.other], 560)
        XCTAssertEqual(counts.values.reduce(0, +), 902)
    }

    // MARK: - Invariant 8

    func testEveryRegisteredModelsTaskAgreesWithTheLiveType() throws {
        let registered = try Self.registeredTasks()
        let live = try AIMLModelsFixture.wireTypesBySpelling()

        var disagreements: [String] = []
        var classifiedAsNonGeneration: [String] = []
        var unserved: [String] = []
        var served = 0

        for (spelling, task) in registered {
            guard let families = live[spelling] else { unserved.append(spelling); continue }
            served += 1
            let wire = AIMLEndpoints.wireTask(forEndpointFamilies: families)
            guard let wireTask = AIMLEndpoints.createTask(for: wire) else {
                classifiedAsNonGeneration.append("\(spelling) -> \(families.sorted())")
                continue
            }
            if wireTask != task {
                disagreements.append(
                    "\(spelling): registry says \(task.rawValue), wire says \(wire.rawValue) "
                    + "via \(families.sorted())")
            }
        }

        XCTAssertEqual(
            classifiedAsNonGeneration.sorted(), [],
            "a model we ship classifies as a non-generation endpoint family. Either the registry "
            + "ships something that is not a generation model, or a generation family is missing "
            + "from AIMLEndpoints.imageEndpointFamilies / .videoEndpointFamilies.")
        XCTAssertEqual(
            disagreements.sorted(), [],
            "spec § 3.6 invariant 8: the registry and the live endpoint disagree about these models")
        XCTAssertEqual(served, Self.registeredSpellingsServed)
        XCTAssertEqual(unserved.sorted(), (Self.registeredSpellingsNotServed + ["alibaba/wan-3-0-video", "minimax/h3-max", "gpt-image-2.5-flare", "gpt-image-2.5-sunburst", "openai/gpt-image-2.5-flare", "openai/gpt-image-2.5-sunburst"]).sorted(),
                       "this is Task 22's delete list; it changed")
    }
}
