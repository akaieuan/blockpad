import XCTest
@testable import BlockpadKit

final class HexColorTests: XCTestCase {
    func testParsesSixDigitHexWithAndWithoutHash() {
        let a = HexColor.components("#55677A")
        let b = HexColor.components("55677a")
        XCTAssertEqual(a?.r ?? 0, 0x55 / 255.0, accuracy: 0.001)
        XCTAssertEqual(a?.g ?? 0, 0x67 / 255.0, accuracy: 0.001)
        XCTAssertEqual(a?.b ?? 0, 0x7A / 255.0, accuracy: 0.001)
        XCTAssertEqual(a?.r ?? 0, b?.r ?? 1, accuracy: 0.0001)
    }

    func testExpandsThreeDigitShorthand() {
        let short = HexColor.components("#F0A")
        let long = HexColor.components("#FF00AA")
        XCTAssertEqual(short?.r ?? 0, long?.r ?? 1, accuracy: 0.0001)
        XCTAssertEqual(short?.g ?? 1, long?.g ?? 0, accuracy: 0.0001)
        XCTAssertEqual(short?.b ?? 0, long?.b ?? 1, accuracy: 0.0001)
    }

    func testParsesAlpha() {
        XCTAssertEqual(HexColor.components("#00000080")?.a ?? 0, 128 / 255.0, accuracy: 0.001)
        XCTAssertEqual(HexColor.components("#000000")?.a ?? 0, 1, accuracy: 0.0001)
    }

    func testRejectsGarbage() {
        XCTAssertNil(HexColor.components("nope"))
        XCTAssertNil(HexColor.components("#12345"))
        XCTAssertNil(HexColor.components(""))
        XCTAssertNil(HexColor.components("#GGGGGG"))
    }

    func testRoundTripsThroughAString() {
        XCTAssertEqual(HexColor.normalized("#55677a"), "#55677A")
        XCTAssertEqual(HexColor.normalized("f0a"), "#FF00AA")
        XCTAssertEqual(HexColor.string(r: 1, g: 0, b: 0), "#FF0000")
    }

    func testClampsOutOfRangeComponents() {
        XCTAssertEqual(HexColor.string(r: 2, g: -1, b: 0.5), "#FF0080")
    }
}
