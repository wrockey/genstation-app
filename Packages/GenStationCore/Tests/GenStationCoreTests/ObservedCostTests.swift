// Observed per-model cost (design § 4.5). There is no estimate table and there will not be one:
// the captured /models response publishes no pricing field of any kind, which is what the app has
// been saying since before anyone checked (MCPService.swift:1404-1405).
//
// These tests cover the arithmetic and the canonicalisation. They cannot see the display — that is
// app-side and on the live-test checklist, like every other display half in this stage.

import XCTest
@testable import GenStationCore

final class ObservedCostTests: XCTestCase {

    private func item(_ model: String?, _ cost: Double?) -> HistoryEntry {
        .item(HistoryItem(prompt: "p", date: Date(), modelUsed: model, costUSD: cost))
    }

    /// An alias spelling that resolves to a different canonical id. Skips the test rather than
    /// asserting a hardcoded pair, because Task 11 chose which spelling is canonical and Task 22
    /// may remove ids.
    private func aliasPair() throws -> (alias: String, canonical: String) {
        for model in Catalog.all where !model.aliases.isEmpty {
            if let alias = model.aliases.first(where: { $0 != model.id }) {
                return (alias, model.id)
            }
        }
        throw XCTSkip("no alias groups in the catalog yet — this test needs Task 11")
    }

    func testNoSamplesProducesNoEntry() {
        XCTAssertTrue(ObservedCostIndex.build(fromSamples: []).isEmpty)
        XCTAssertTrue(ObservedCostIndex.build(from: []).isEmpty)
    }

    /// A run with no recorded cost tells us nothing about cost, so it must neither dilute the mean
    /// nor inflate the sample size. "3 runs" must mean "3 runs we have a price for".
    func testASampleWithNoCostIsNotCounted() {
        let index = ObservedCostIndex.build(fromSamples: [
            CostSample(modelID: "a", costUSD: 0.02),
            CostSample(modelID: "a", costUSD: nil),
        ])
        XCTAssertEqual(index["a"]?.sampleCount, 1)
        XCTAssertEqual(index["a"]?.totalUSD ?? 0, 0.02, accuracy: 1e-9)
    }

    func testASampleWithNoModelIsIgnored() {
        let index = ObservedCostIndex.build(fromSamples: [
            CostSample(modelID: nil, costUSD: 0.02),
            CostSample(modelID: "", costUSD: 0.02),
        ])
        XCTAssertTrue(index.isEmpty)
    }

    func testOneSampleReportsItselfAsTheMean() {
        let index = ObservedCostIndex.build(fromSamples: [CostSample(modelID: "a", costUSD: 0.25)])
        XCTAssertEqual(index["a"]?.sampleCount, 1)
        XCTAssertEqual(index["a"]?.meanUSD ?? 0, 0.25, accuracy: 1e-9)
    }

    func testSeveralSamplesAverage() {
        let index = ObservedCostIndex.build(fromSamples: [
            CostSample(modelID: "a", costUSD: 0.10),
            CostSample(modelID: "a", costUSD: 0.20),
            CostSample(modelID: "a", costUSD: 0.30),
        ])
        XCTAssertEqual(index["a"]?.sampleCount, 3)
        XCTAssertEqual(index["a"]?.totalUSD ?? 0, 0.60, accuracy: 1e-9)
        XCTAssertEqual(index["a"]?.meanUSD ?? 0, 0.20, accuracy: 1e-9)
    }

    /// The whole reason the arithmetic is in the package. `modelUsed` keeps whatever spelling the
    /// generation was made under, forever, and after the collapse most of those spellings are
    /// aliases. Keying on the raw string would split one model's history across several rows and
    /// show "1 run" for a model the user has run twenty times.
    func testAliasSpellingsFoldIntoTheCanonicalRow() throws {
        let pair = try aliasPair()
        let index = ObservedCostIndex.build(fromSamples: [
            CostSample(modelID: pair.alias, costUSD: 0.10),
            CostSample(modelID: pair.canonical, costUSD: 0.30),
            CostSample(modelID: pair.alias.uppercased(), costUSD: 0.20),
        ])
        XCTAssertNil(index[pair.alias], "the alias must not key its own entry")
        XCTAssertEqual(index[pair.canonical]?.sampleCount, 3)
        XCTAssertEqual(index[pair.canonical]?.meanUSD ?? 0, 0.20, accuracy: 1e-9)
        XCTAssertEqual(ObservedCostIndex.cost(for: pair.alias, in: index)?.sampleCount, 3,
                       "a lookup by alias must find the canonical entry")
    }

    func testAnUnknownModelKeysOnItsLowercasedID() {
        XCTAssertNil(Catalog.canonicalID(for: "alibaba/qwen-image-3"),
                     "this id must stay unregistered, or the test proves nothing")
        let index = ObservedCostIndex.build(fromSamples: [
            CostSample(modelID: "Alibaba/Qwen-Image-3", costUSD: 0.05),
            CostSample(modelID: "alibaba/qwen-image-3", costUSD: 0.15),
        ])
        XCTAssertEqual(index["alibaba/qwen-image-3"]?.sampleCount, 2)
        XCTAssertEqual(index["alibaba/qwen-image-3"]?.meanUSD ?? 0, 0.10, accuracy: 1e-9)
    }

    func testFolderedHistoryIsWalkedRecursively() {
        let nested = HistoryEntry.folder(Folder(name: "inner", children: [
            item("a", 0.30),
            item("a", 0.10),
        ]))
        let index = ObservedCostIndex.build(from: [
            item("a", 0.20),
            .folder(Folder(name: "outer", children: [nested, item("b", 1.00)])),
        ])
        XCTAssertEqual(index["a"]?.sampleCount, 3)
        XCTAssertEqual(index["a"]?.meanUSD ?? 0, 0.20, accuracy: 1e-9)
        XCTAssertEqual(index["b"]?.sampleCount, 1)
    }

    func testMeanIsNilForAZeroCountValue() {
        // The index never stores one, but a hand-built value must not divide by zero.
        XCTAssertNil(ObservedCost(totalUSD: 0, sampleCount: 0).meanUSD)
    }
}
