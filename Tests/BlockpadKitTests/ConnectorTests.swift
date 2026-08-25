import XCTest
import CoreGraphics
@testable import BlockpadKit

/// These exist because connectors only worked in one quadrant. CGRect
/// standardizes on almost every accessor, so the sign that carries a
/// connector's direction kept getting thrown away.
final class ConnectorTests: XCTestCase {

    private let start = CGPoint(x: 200, y: 200)

    /// A connector must be able to point anywhere, not just down and right.
    func testEveryDirectionSurvivesAReadBack() {
        for degrees in stride(from: 0, to: 360, by: 15) {
            let radians = CGFloat(degrees) * .pi / 180
            let rect = Connector.rect(from: start, angle: radians, length: 120)
            let readBack = Connector.angle(of: rect) * 180 / .pi
            let normalized = (readBack + 360).truncatingRemainder(dividingBy: 360)
            XCTAssertEqual(normalized, CGFloat(degrees), accuracy: 0.001,
                           "connector at \(degrees)° read back as \(normalized)°")
            XCTAssertEqual(Connector.length(of: rect), 120, accuracy: 0.001)
        }
    }

    /// The specific failure: CGRect.maxX standardizes, so a negative width
    /// collapsed the vector.
    func testNegativeSizeIsNotStandardizedAway() {
        let rect = CGRect(x: 200, y: 200, width: -100, height: -50)
        let (a, b) = Connector.endpoints(of: rect)
        XCTAssertEqual(a, CGPoint(x: 200, y: 200))
        XCTAssertEqual(b, CGPoint(x: 100, y: 150))
        // What the old code did, for contrast:
        XCTAssertEqual(CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: 200, y: 200))
    }

    /// Moving a connector must not flip it. CGRect.offsetBy standardizes.
    func testTranslateKeepsDirection() {
        for degrees in stride(from: 0, to: 360, by: 45) {
            let radians = CGFloat(degrees) * .pi / 180
            let rect = Connector.rect(from: start, angle: radians, length: 90)
            let moved = Connector.translate(rect, dx: -37, dy: 61)
            XCTAssertEqual(Connector.angle(of: moved), Connector.angle(of: rect), accuracy: 0.001)
            XCTAssertEqual(Connector.length(of: moved), 90, accuracy: 0.001)
        }
    }

    func testOffsetByWouldHaveFlippedIt() {
        let rect = CGRect(x: 200, y: 200, width: -100, height: -50)
        XCTAssertEqual(rect.offsetBy(dx: 10, dy: 10).size.width, 100)   // sign lost
        XCTAssertEqual(Connector.translate(rect, dx: 10, dy: 10).size.width, -100)
    }

    /// Dragging either end must leave the other end where it was.
    func testDraggingAnEndKeepsTheOtherPut() {
        let rect = Connector.rect(from: start, angle: .pi * 0.75, length: 100)
        let (a, b) = Connector.endpoints(of: rect)
        let movedEnd = CGRect(x: a.x, y: a.y, width: 10 - a.x, height: -40 - a.y)
        XCTAssertEqual(Connector.endpoints(of: movedEnd).start, a)
        let movedStart = CGRect(x: 5, y: 7, width: b.x - 5, height: b.y - 7)
        XCTAssertEqual(Connector.endpoints(of: movedStart).end.x, b.x, accuracy: 0.001)
        XCTAssertEqual(Connector.endpoints(of: movedStart).end.y, b.y, accuracy: 0.001)
    }

    // MARK: - Angle snapping

    func testAngleSnapHitsEveryFifteenDegreeSpoke() {
        for degrees in stride(from: -180, through: 180, by: 5) {
            let radians = CGFloat(degrees) * .pi / 180
            let loose = CGPoint(x: start.x + cos(radians) * 80, y: start.y + sin(radians) * 80)
            let snapped = Connector.snapToAngle(loose, around: start)
            let angle = atan2(snapped.y - start.y, snapped.x - start.x) * 180 / .pi
            // Distance to the nearest spoke, not the raw remainder: fmod(-15, 15)
            // is -15 in floating point, not 0.
            let spokes = angle / 15
            XCTAssertEqual(abs(spokes - spokes.rounded()), 0, accuracy: 0.0001,
                           "\(degrees)° snapped to \(angle)°, which is not a spoke")
            XCTAssertEqual(hypot(snapped.x - start.x, snapped.y - start.y), 80, accuracy: 0.001)
        }
    }

    func testAngleSnapWorksInEveryQuadrant() {
        let cases: [(CGFloat, CGFloat)] = [(1, 1), (-1, 1), (1, -1), (-1, -1)]
        for (sx, sy) in cases {
            let loose = CGPoint(x: start.x + 62 * sx, y: start.y + 59 * sy)
            let snapped = Connector.snapToAngle(loose, around: start)
            XCTAssertEqual((snapped.x - start.x).sign, (loose.x - start.x).sign)
            XCTAssertEqual((snapped.y - start.y).sign, (loose.y - start.y).sign)
        }
    }

    // MARK: - Curve

    func testStraightConnectorHasNoBow() {
        let rect = Connector.rect(from: start, angle: 0.4, length: 140)
        let mid = Connector.point(on: rect, curve: 0, at: 0.5)
        let (a, b) = Connector.endpoints(of: rect)
        XCTAssertEqual(mid.x, (a.x + b.x) / 2, accuracy: 0.001)
        XCTAssertEqual(mid.y, (a.y + b.y) / 2, accuracy: 0.001)
    }

    /// A bowed connector still starts and ends exactly where it should.
    func testCurveKeepsBothEndpoints() {
        let rect = Connector.rect(from: start, angle: 2.1, length: 130)
        let (a, b) = Connector.endpoints(of: rect)
        for curve in [-0.6, -0.2, 0.2, 0.6] {
            let atStart = Connector.point(on: rect, curve: curve, at: 0)
            let atEnd = Connector.point(on: rect, curve: curve, at: 1)
            XCTAssertEqual(atStart.x, a.x, accuracy: 0.001)
            XCTAssertEqual(atStart.y, a.y, accuracy: 0.001)
            XCTAssertEqual(atEnd.x, b.x, accuracy: 0.001)
            XCTAssertEqual(atEnd.y, b.y, accuracy: 0.001)
        }
    }

    /// The sign of the curve picks a side, and the magnitude sets how far.
    func testCurveSignPicksOppositeSides() {
        let rect = Connector.rect(from: start, angle: 0, length: 100)
        let up = Connector.point(on: rect, curve: 0.3, at: 0.5)
        let down = Connector.point(on: rect, curve: -0.3, at: 0.5)
        XCTAssertGreaterThan(up.y, start.y)
        XCTAssertLessThan(down.y, start.y)
        XCTAssertEqual(up.y - start.y, start.y - down.y, accuracy: 0.001)

        let gentle = Connector.point(on: rect, curve: 0.15, at: 0.5)
        XCTAssertLessThan(gentle.y - start.y, up.y - start.y)
    }

    /// A zero-length connector must not divide by zero working out its bow.
    func testDegenerateConnectorHasFiniteGeometry() {
        let rect = CGRect(x: 50, y: 50, width: 0, height: 0)
        let c = Connector.control(of: rect, curve: 0.5)
        XCTAssertTrue(c.x.isFinite && c.y.isFinite)
        XCTAssertEqual(Connector.length(of: rect), 0)
    }
}
