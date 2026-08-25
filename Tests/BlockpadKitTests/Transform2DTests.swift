import XCTest
import CoreGraphics
@testable import BlockpadKit

final class Transform2DTests: XCTestCase {

    private let box = CGRect(x: 100, y: 100, width: 200, height: 120)
    private var centre: CGPoint { CGPoint(x: box.midX, y: box.midY) }

    // MARK: - Identity

    func testIdentityLeavesEveryPointWhereItWas() {
        let m = Transform2D.identity.matrix(about: centre)
        for p in [box.origin, CGPoint(x: box.maxX, y: box.maxY), centre] {
            let moved = p.applying(m)
            XCTAssertEqual(moved.x, p.x, accuracy: 1e-9)
            XCTAssertEqual(moved.y, p.y, accuracy: 1e-9)
        }
    }

    func testIdentityIsRecognised() {
        XCTAssertTrue(Transform2D().isIdentity)
        XCTAssertNil(Transform2D().token)
        XCTAssertFalse(Transform2D(rotation: 1).isIdentity)
        XCTAssertFalse(Transform2D(scaleY: 0.9).isIdentity)
    }

    /// The centre is the anchor, so it never moves however the block is tilted.
    func testCentreIsFixedUnderEveryTransform() {
        let cases = [Transform2D(rotation: 37),
                     Transform2D(skewX: -22),
                     Transform2D(skewY: 14),
                     Transform2D(scaleY: 0.5),
                     Transform2D(.isoTop)]
        for t in cases {
            let moved = centre.applying(t.matrix(about: centre))
            XCTAssertEqual(moved.x, centre.x, accuracy: 1e-6)
            XCTAssertEqual(moved.y, centre.y, accuracy: 1e-6)
        }
    }

    // MARK: - Invertibility

    /// Hit testing runs through the inverse, so it has to be exact.
    func testInverseUndoesTheTransform() {
        let cases = [Transform2D(rotation: 15),
                     Transform2D(rotation: -80, skewX: 12),
                     Transform2D(skewX: -30, skewY: 30, scaleX: 0.9, scaleY: 0.866),
                     Transform2D(.isoLeft),
                     Transform2D(.isoRight),
                     Transform2D(.isoTop)]
        for t in cases {
            let forward = t.matrix(about: centre)
            let back = t.inverse(about: centre)
            for p in [box.origin, CGPoint(x: box.maxX, y: box.minY), CGPoint(x: 512, y: 7)] {
                let round = p.applying(forward).applying(back)
                XCTAssertEqual(round.x, p.x, accuracy: 1e-6)
                XCTAssertEqual(round.y, p.y, accuracy: 1e-6)
            }
        }
    }

    /// A flattened plane is reachable by dragging, and must not crash or NaN.
    func testDegenerateTransformDoesNotProduceNaN() {
        let t = Transform2D(scaleY: 0)
        let inverse = t.inverse(about: centre)
        XCTAssertTrue(inverse.a.isFinite && inverse.d.isFinite)
        let corners = t.corners(of: box)
        XCTAssertTrue(corners.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        XCTAssertFalse(t.contains(CGPoint(x: 1e6, y: 1e6), in: box))
    }

    // MARK: - Shape

    /// A rectangle stays a parallelogram: opposite sides equal and parallel.
    /// That is the affine guarantee, and the whole reason for choosing it.
    func testTiltedRectIsStillAParallelogram() {
        for t in [Transform2D(rotation: 23), Transform2D(.isoTop),
                  Transform2D(skewX: 18, scaleX: 0.8, scaleY: 0.7)] {
            let c = t.corners(of: box)
            let top = CGPoint(x: c[1].x - c[0].x, y: c[1].y - c[0].y)
            let bottom = CGPoint(x: c[2].x - c[3].x, y: c[2].y - c[3].y)
            XCTAssertEqual(top.x, bottom.x, accuracy: 1e-6)
            XCTAssertEqual(top.y, bottom.y, accuracy: 1e-6)

            let left = CGPoint(x: c[3].x - c[0].x, y: c[3].y - c[0].y)
            let right = CGPoint(x: c[2].x - c[1].x, y: c[2].y - c[1].y)
            XCTAssertEqual(left.x, right.x, accuracy: 1e-6)
            XCTAssertEqual(left.y, right.y, accuracy: 1e-6)
        }
    }

    func testRotationTurnsTheBoxWithoutResizingIt() {
        let t = Transform2D(rotation: 90)
        let c = t.corners(of: box)
        let edge = hypot(c[1].x - c[0].x, c[1].y - c[0].y)
        XCTAssertEqual(edge, box.width, accuracy: 1e-6)
    }

    func testForeshorteningShortensOnlyTheVerticalAxis() {
        let t = Transform2D(scaleY: 0.5)
        let c = t.corners(of: box)
        XCTAssertEqual(hypot(c[1].x - c[0].x, c[1].y - c[0].y), box.width, accuracy: 1e-6)
        XCTAssertEqual(hypot(c[3].x - c[0].x, c[3].y - c[0].y), box.height * 0.5, accuracy: 1e-6)
    }

    /// The three faces must match the isometric projection axes, not merely
    /// lean. An unforeshortened parallelogram reads as a skewed rectangle.
    func testIsometricFacesMatchTheProjectionAxes() {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let expected: [Transform2D.Preset: (CGFloat, CGFloat, CGFloat, CGFloat)] = [
            .isoTop:   (0.8660254, -0.5, 0.8660254, 0.5),
            .isoLeft:  (0.8660254,  0.5, 0,         1),
            .isoRight: (0.8660254, -0.5, 0,         1)
        ]
        for (preset, target) in expected {
            let m = preset.transform.matrix(about: CGPoint(x: unit.midX, y: unit.midY))
            XCTAssertEqual(m.a, target.0, accuracy: 1e-6, "\(preset) a")
            XCTAssertEqual(m.b, target.1, accuracy: 1e-6, "\(preset) b")
            XCTAssertEqual(m.c, target.2, accuracy: 1e-6, "\(preset) c")
            XCTAssertEqual(m.d, target.3, accuracy: 1e-6, "\(preset) d")
        }
    }

    /// None of the faces may mirror — a negative determinant flips text.
    func testIsometricFacesDoNotMirror() {
        for preset in [Transform2D.Preset.isoTop, .isoLeft, .isoRight] {
            let m = preset.transform.matrix(about: .zero)
            XCTAssertGreaterThan(m.a * m.d - m.b * m.c, 0, "\(preset) mirrors")
        }
    }

    /// The isometric faces must actually differ from each other and from flat.
    func testIsometricFacesAreDistinct() {
        let shapes = [Transform2D.Preset.isoTop, .isoLeft, .isoRight].map { $0.transform.corners(of: box) }
        XCTAssertNotEqual(shapes[0], shapes[1])
        XCTAssertNotEqual(shapes[1], shapes[2])
        XCTAssertNotEqual(shapes[0], shapes[2])
        for shape in shapes {
            XCTAssertNotEqual(shape, Transform2D.identity.corners(of: box))
        }
    }

    // MARK: - Bounds and hit testing

    func testBoundsOfAnUntiltedRectIsTheRect() {
        let b = Transform2D.identity.bounds(of: box)
        XCTAssertEqual(b.minX, box.minX, accuracy: 1e-9)
        XCTAssertEqual(b.maxY, box.maxY, accuracy: 1e-9)
    }

    func testRotatingGrowsTheAxisAlignedBounds() {
        let b = Transform2D(rotation: 45).bounds(of: box)
        XCTAssertGreaterThan(b.width, box.width)
        XCTAssertGreaterThan(b.height, box.height)
    }

    /// The point of inverting rather than approximating: a click near a tilted
    /// corner must land correctly.
    func testHitTestingFollowsTheTilt() {
        let t = Transform2D(rotation: 45)
        XCTAssertTrue(t.contains(centre, in: box))

        // A corner of the untilted rect is outside the rotated one...
        XCTAssertFalse(t.contains(box.origin, in: box))
        // ...and each rotated corner is on the tilted shape.
        for corner in t.corners(of: box) {
            XCTAssertTrue(t.contains(corner, in: box, slop: 0.001))
        }
    }

    // MARK: - Payload

    func testPresetsEmitTheirName() {
        XCTAssertEqual(Transform2D(.isoTop).token, "iso-top")
        XCTAssertEqual(Transform2D(.isoLeft).token, "iso-left")
        XCTAssertEqual(Transform2D(.isoRight).token, "iso-right")
        XCTAssertNil(Transform2D(.flat).token)
    }

    func testFreeTransformEmitsItsNumbers() {
        XCTAssertEqual(Transform2D(rotation: 12).token, "rot 12°")
        XCTAssertEqual(Transform2D(skewX: -8, skewY: 4).token, "skew -8,4")
        XCTAssertEqual(Transform2D(scaleY: 0.75).token, "flat 100,75%")
    }

    func testPresetIsRecognisedBackFromItsValues() {
        XCTAssertEqual(Transform2D(.isoTop).preset, .isoTop)
        XCTAssertNil(Transform2D(rotation: 3).preset)
    }

    // MARK: - Migration

    /// A scene written before planes existed has no transform at all.
    func testMissingFieldsDecodeToIdentity() throws {
        let data = "{}".data(using: .utf8)!
        let t = try JSONDecoder().decode(Transform2D.self, from: data)
        XCTAssertTrue(t.isIdentity)
        XCTAssertEqual(t.scaleY, 1)
    }

    func testRoundTripsThroughJSON() throws {
        let original = Transform2D(rotation: 17, skewX: -5, skewY: 2, scaleY: 0.8)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(Transform2D.self, from: data), original)
    }
}
