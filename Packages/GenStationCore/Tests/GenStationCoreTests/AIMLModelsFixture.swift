// The captured live `GET /models` response, and the only place its path is spelled.
//
// The fixture is NOT created by this file's task. It was captured on 2026-07-27 and committed at
// `b16f840`, together with 167 per-model OpenAPI schemas and a `Fixtures/README.md` that documents
// the capture, the secret sweep and the normalisation. This helper only reads it.
//
// It is the first machine-readable statement in this repository about what the AI/ML API serves, and
// it is the input to Task 22's delete list: a registered id absent from `servedIDsAndAliases()` is a
// deletion candidate, and a served-but-superseded id gets `lifecycle = .superseded` instead.
//
// Re-capturing is allowed but is never silent: it moves the pinned counts in
// `AIMLModelsFixtureTests` and must be its own reviewed commit that says what changed on the wire.
// The exact commands are in the Stage 3 plan, Task 6's RE-CAPTURE APPENDIX.
//
// Read through a `#filePath`-relative URL rather than `Bundle.module`, because `Fixtures/` is
// `exclude:`d from the test target in `Package.swift` and is therefore in no bundle. Same idiom as
// `TableCoverageTests.registryURL`.

import Foundation
@testable import GenStationCore

enum AIMLModelsFixture {

    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/aiml-models-response.json")
            .standardizedFileURL
    }

    static func data() throws -> Data {
        try Data(contentsOf: url)
    }

    static func response() throws -> AIMLEndpoints.ModelsResponse {
        try JSONDecoder().decode(AIMLEndpoints.ModelsResponse.self, from: data())
    }

    /// Entry dictionaries straight from `JSONSerialization`, bypassing the decode under test — this
    /// is what makes the losslessness assertion mean something rather than comparing the decode to
    /// itself.
    static func rawEntries() throws -> [[String: Any]] {
        let object = try JSONSerialization.jsonObject(with: try data())
        guard let root = object as? [String: Any],
              let array = root["data"] as? [[String: Any]] else {
            throw NSError(
                domain: "AIMLModelsFixture", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                            "fixture at \(url.path) has no top-level `data` array"])
        }
        return array
    }

    /// Every id the live endpoint served, lowercased. 762 of them.
    static func servedIDs() throws -> Set<String> {
        Set(try response().data.map { $0.id.lowercased() })
    }

    /// Every id *and* alias the live endpoint served, lowercased. 1415 spellings.
    ///
    /// Task 22's delete list subtracts from this set, not from `servedIDs()` — a registry key is
    /// frequently an alias of a canonical served id, and subtracting from the narrower set would
    /// authorise deleting models that are alive.
    static func servedIDsAndAliases() throws -> Set<String> {
        var out: Set<String> = []
        for entry in try response().data {
            out.insert(entry.id.lowercased())
            for alias in entry.aliases ?? [] { out.insert(alias.lowercased()) }
        }
        return out
    }

    /// Spelling (id or alias, lowercased) -> **every** endpoint family that serves it.
    ///
    /// A set, not a value: 91 captured ids are served on more than one family. Classify with
    /// `AIMLEndpoints.wireTask(forEndpointFamilies:)`.
    static func wireTypesBySpelling() throws -> [String: Set<String>] {
        var out: [String: Set<String>] = [:]
        for entry in try response().data {
            guard let type = entry.type else { continue }
            out[entry.id.lowercased(), default: []].insert(type)
            for alias in entry.aliases ?? [] {
                out[alias.lowercased(), default: []].insert(type)
            }
        }
        return out
    }

    /// Spelling -> the `info` block of the entry that best describes it.
    ///
    /// When one spelling is served on several endpoint families it has several `info` blocks with
    /// different names (`"Gemini 2.5 Flash Image"` on `image-generations`, `"Nano Banana (Gemini 2.5
    /// Flash Image)"` on `chat-completions`). The winner is chosen by
    /// `AIMLEndpoints.infoPreferenceOrder`, then by lexicographically smallest `type`, so the answer
    /// never depends on the order entries happen to appear in the JSON.
    static func infoBySpelling() throws -> [String: AIMLEndpoints.ModelEntry.Info] {
        var best: [String: (rank: Int, type: String, info: AIMLEndpoints.ModelEntry.Info)] = [:]
        for entry in try response().data {
            guard let info = entry.info else { continue }
            let type = entry.type ?? ""
            let rank = AIMLEndpoints.infoPreferenceOrder.firstIndex(of: type)
                ?? AIMLEndpoints.infoPreferenceOrder.count
            for spelling in [entry.id] + (entry.aliases ?? []) {
                let key = spelling.lowercased()
                if let current = best[key],
                   (current.rank, current.type) <= (rank, type) { continue }
                best[key] = (rank, type, info)
            }
        }
        return best.mapValues { $0.info }
    }
}
