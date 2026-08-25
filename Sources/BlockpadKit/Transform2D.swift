import Foundation
import CoreGraphics

/// A block's tilt: rotation, skew and foreshortening about its own centre.
///
/// Deliberately affine rather than a free quadrilateral. An affine transform
/// maps one-to-one onto a CSS `transform`, so the receiving agent gets a line it
/// can paste; a general quad is projective and can only be approximated. Keeping
/// the rect also keeps alignment, snapping, resize and run detection working —
/// none of which have an answer for the left edge of an arbitrary quad.
public struct Transform2D: Codable, Equatable {
    /// Degrees, clockwise on screen.
    public var rotation: Double
    /// Degrees. Positive leans the top edge to the right.
    public var skewX: Double
    /// Degrees. Positive leans the left edge downward.
    public var skewY: Double
    /// Horizontal foreshortening.
    public var scaleX: Double
    /// Vertical foreshortening. Under 1 lays the plane away from the viewer,
    /// which is most of what makes a tilt read as depth rather than as rotation.
    ///
    /// Both axes are needed: without `scaleX` the isometric faces are not
    /// expressible at all, and they come out as unforeshortened parallelograms
    /// that lean without reading as a cube.
    public var scaleY: Double

    public init(rotation: Double = 0, skewX: Double = 0, skewY: Double = 0,
                scaleX: Double = 1, scaleY: Double = 1) {
        self.rotation = rotation
        self.skewX = skewX
        self.skewY = skewY
        self.scaleX = scaleX
        self.scaleY = scaleY
    }

    public static let identity = Transform2D()

    public var isIdentity: Bool {
        rotation == 0 && skewX == 0 && skewY == 0 && scaleX == 1 && scaleY == 1
    }

    /// Every field decodes to its identity value, so a scene written before
    /// planes existed opens with no tilt rather than failing.
    private enum CodingKeys: String, CodingKey {
        case rotation, skewX, skewY, scaleX, scaleY
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        skewX = try c.decodeIfPresent(Double.self, forKey: .skewX) ?? 0
        skewY = try c.decodeIfPresent(Double.self, forKey: .skewY) ?? 0
        scaleX = try c.decodeIfPresent(Double.self, forKey: .scaleX) ?? 1
        scaleY = try c.decodeIfPresent(Double.self, forKey: .scaleY) ?? 1
    }

    // MARK: - Presets

    /// The three isometric faces, plus flat. These exist because nobody wants to
    /// dial in -30°, 30° and 0.866 by hand, and because a named face is what the
    /// payload should say — `iso-top` tells an agent something four coordinates
    /// never could.
    public enum Preset: String, CaseIterable, Sendable {
        case flat, isoTop, isoLeft, isoRight

        public var label: String {
            switch self {
            case .flat: return "Flat"
            case .isoTop: return "Top"
            case .isoLeft: return "Left"
            case .isoRight: return "Right"
            }
        }

        /// The wire name, and what the tree emits.
        public var token: String {
            switch self {
            case .flat: return "flat"
            case .isoTop: return "iso-top"
            case .isoLeft: return "iso-left"
            case .isoRight: return "iso-right"
            }
        }

        public var transform: Transform2D {
            switch self {
            case .flat:
                return .identity
            // Solved from the isometric projection axes on a y-down canvas —
            // x runs (0.866, ∓0.5) and z runs straight down — then expressed in
            // this struct's shear-then-scale form. Verified by round-tripping
            // the target matrices, not by eye.
            case .isoTop:
                return Transform2D(rotation: 0, skewX: 45, skewY: -45,
                                   scaleX: 0.8660254, scaleY: 0.5)
            case .isoLeft:
                return Transform2D(rotation: 0, skewX: 0, skewY: 26.565051,
                                   scaleX: 0.8660254, scaleY: 1)
            case .isoRight:
                return Transform2D(rotation: 0, skewX: 0, skewY: -26.565051,
                                   scaleX: 0.8660254, scaleY: 1)
            }
        }
    }

    /// The preset this transform matches, if it matches one exactly. Lets the
    /// inspector show a face as selected, and the export emit `iso-top` rather
    /// than three numbers that happen to equal it.
    public var preset: Preset? {
        Preset.allCases.first { $0.transform == self }
    }

    public init(_ preset: Preset) {
        self = preset.transform
    }

    // MARK: - Matrix

    /// The affine matrix, about `centre`.
    ///
    /// Order matters and is fixed: skew, then vertical scale, then rotation.
    /// Rotating first would turn a horizontal skew into a diagonal one and the
    /// isometric presets would stop being isometric.
    public func matrix(about centre: CGPoint) -> CGAffineTransform {
        var t = CGAffineTransform(translationX: centre.x, y: centre.y)
        t = t.rotated(by: CGFloat(rotation) * .pi / 180)
        t = t.scaledBy(x: CGFloat(scaleX), y: CGFloat(scaleY))
        t = t.concatenating(.identity)
        let sx = CGFloat(tan(skewX * .pi / 180))
        let sy = CGFloat(tan(skewY * .pi / 180))
        let shear = CGAffineTransform(a: 1, b: sy, c: sx, d: 1, tx: 0, ty: 0)
        t = shear.concatenating(t)
        return t.translatedBy(x: -centre.x, y: -centre.y)
    }

    /// The inverse, for turning a click back into the block's own space. Returns
    /// identity rather than crashing when the matrix is singular — a zero
    /// `scaleY` is reachable by dragging.
    public func inverse(about centre: CGPoint) -> CGAffineTransform {
        let m = matrix(about: centre)
        guard abs(m.a * m.d - m.b * m.c) > 1e-9 else { return .identity }
        return m.inverted()
    }

    /// The four corners of `rect` once tilted, in the order top-left,
    /// top-right, bottom-right, bottom-left.
    public func corners(of rect: CGRect) -> [CGPoint] {
        let m = matrix(about: CGPoint(x: rect.midX, y: rect.midY))
        return [CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY)].map { $0.applying(m) }
    }

    /// The axis-aligned box the tilted rect actually occupies. Selection chrome
    /// and zoom-to-fit need this; the untilted rect is wrong once tilted.
    public func bounds(of rect: CGRect) -> CGRect {
        let points = corners(of: rect)
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!,
                      width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// Whether a point in canvas space falls inside the tilted rect.
    public func contains(_ point: CGPoint, in rect: CGRect, slop: CGFloat = 0) -> Bool {
        let local = point.applying(inverse(about: CGPoint(x: rect.midX, y: rect.midY)))
        return rect.insetBy(dx: -slop, dy: -slop).contains(local)
    }

    /// How the tree names this tilt. `nil` when there is nothing to say.
    public var token: String? {
        if isIdentity { return nil }
        if let preset, preset != .flat { return preset.token }
        var parts: [String] = []
        if rotation != 0 { parts.append("rot \(Int(rotation.rounded()))°") }
        if skewX != 0 || skewY != 0 {
            parts.append("skew \(Int(skewX.rounded())),\(Int(skewY.rounded()))")
        }
        if scaleX != 1 || scaleY != 1 {
            parts.append("flat \(Int((scaleX * 100).rounded())),\(Int((scaleY * 100).rounded()))%")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
