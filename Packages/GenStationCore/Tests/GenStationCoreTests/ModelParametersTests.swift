import XCTest
@testable import GenStationCore

/// Characterization tests for `ModelParameters`, added when it moved out of the app target and into
/// the package (Stage 2 Task 4). They pin *what the struct does today*, not what it ought to do —
/// the descriptor tables that Stage 2 generates read these defaults, so a silent change to one of
/// them would shift the payload of every model that leaves the field alone.
final class ModelParametersTests: XCTestCase {

    func testFreshParametersCarryTheirDeclaredDefaults() {
        let p = ModelParameters()
        XCTAssertEqual(p.duration, 5)
        XCTAssertEqual(p.resolution, "720p")
        XCTAssertEqual(p.frameRate, 30)
        XCTAssertEqual(p.aspectRatio, "16:9")
        XCTAssertNil(p.guidanceScale)
    }

    /// Pins a known **defect**, deliberately. `acceleration` is a stored property with a non-nil
    /// default of `"regular"`, but it has no entry in `CodingKeys` — so `JSONEncoder` drops it and
    /// it never round-trips. That is wrong, and it is recorded in the Stage 2 drift ledger to be
    /// fixed in a later, reviewed wave.
    ///
    /// It is pinned rather than fixed because Stage 2 freezes behaviour: adding the missing key
    /// mid-refactor would be an unverifiable change buried in a file move. So if you are here
    /// because this test failed, you did not break something — you *fixed* something. Confirm that
    /// was intentional, then update this test and strike the entry from the ledger.
    ///
    /// (Nothing in the repo encodes or decodes `ModelParameters` today, so the defect is inert;
    /// the `Codable` conformance is kept only because removing it would itself be an unverifiable
    /// behaviour change.)
    func testAccelerationIsAbsentFromCodingKeys() throws {
        let json = try JSONEncoder().encode(ModelParameters())
        let dict = try XCTUnwrap(
            JSONSerialization.jsonObject(with: json) as? [String: Any]
        )
        XCTAssertNil(dict["acceleration"])
        // Guard against the assertion above passing vacuously because encoding produced nothing:
        // a sibling key with a non-nil default must be present.
        XCTAssertEqual(dict["resolution"] as? String, "720p")
    }
}
