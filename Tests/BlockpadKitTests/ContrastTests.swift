import XCTest
@testable import BlockpadKit

/// Checked against WCAG's published reference values. A contrast checker that
/// is wrong in the mid-tones is worse than none, because it passes exactly the
/// pairs a person would otherwise have squinted at.
final class ContrastTests: XCTestCase {

    func testLuminanceEndpoints() {
        XCTAssertEqual(HexColor.relativeLuminance("#000000")!, 0, accuracy: 1e-9)
        XCTAssertEqual(HexColor.relativeLuminance("#FFFFFF")!, 1, accuracy: 1e-9)
    }

    /// Mid grey is not 0.5 luminance — that is the whole point of the gamma
    /// expansion, and the trap a naive implementation falls into.
    func testMidGreyIsNotHalfLuminance() {
        let mid = HexColor.relativeLuminance("#808080")!
        XCTAssertEqual(mid, 0.2158, accuracy: 0.0005)
        XCTAssertLessThan(mid, 0.30)
    }

    func testBlackOnWhiteIsTwentyOne() {
        XCTAssertEqual(HexColor.contrastRatio("#000000", "#FFFFFF")!, 21, accuracy: 1e-6)
    }

    func testIdenticalColoursAreOne() {
        XCTAssertEqual(HexColor.contrastRatio("#4488CC", "#4488CC")!, 1, accuracy: 1e-9)
    }

    func testRatioIsSymmetric() {
        let a = HexColor.contrastRatio("#55677A", "#FFFFFF")!
        let b = HexColor.contrastRatio("#FFFFFF", "#55677A")!
        XCTAssertEqual(a, b, accuracy: 1e-9)
    }

    /// The published boundary pair: #767676 on white is the lightest grey that
    /// still clears 4.5:1, and #777777 is the first that does not.
    func testTheFourPointFiveBoundary() {
        let passes = HexColor.contrastRatio("#767676", "#FFFFFF")!
        let fails = HexColor.contrastRatio("#777777", "#FFFFFF")!
        XCTAssertGreaterThanOrEqual(passes, 4.5)
        XCTAssertLessThan(fails, 4.5)
        XCTAssertEqual(passes, 4.54, accuracy: 0.01)
    }

    /// A colour pair from the app's own palette, so the presets are checked too.
    func testPaletteInkOnPaper() {
        let ratio = HexColor.contrastRatio("#2B2A28", "#FBF9F2")!
        XCTAssertGreaterThan(ratio, 4.5)
    }

    func testInvalidHexReturnsNil() {
        XCTAssertNil(HexColor.relativeLuminance("nonsense"))
        XCTAssertNil(HexColor.contrastRatio("#FFFFFF", "zzz"))
    }
}
