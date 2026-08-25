import Foundation
import CoreGraphics
import BlockpadKit

/// Semantic type of a block. The canvas draws these differently, and the tree
/// serializer (§5) reads the same enum, which is why serialization is nearly free.
enum BlockKind: String, Codable, CaseIterable {
    case frame
    case box
    case ellipse
    case diamond
    case text
    case arrow
    case line
    case pen
    case redact

    var label: String {
        switch self {
        case .frame: return "Frame"
        case .box: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .diamond: return "Diamond"
        case .text: return "Text"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .pen: return "Draw"
        case .redact: return "Redact"
        }
    }

    var symbol: String {
        switch self {
        case .frame: return "rectangle.dashed"
        case .box: return "square"
        case .ellipse: return "circle"
        case .diamond: return "diamond"
        case .text: return "character"
        case .arrow: return "arrow.right"
        case .line: return "line.diagonal"
        case .pen: return "pencil"
        case .redact: return "rectangle.fill"
        }
    }

    /// Two-point shapes are defined by a drag vector, not a normalized rect, so
    /// their rect must never be standardized or the direction is lost.
    var isLinear: Bool {
        self == .arrow || self == .line
    }

    var takesFill: Bool {
        switch self {
        case .box, .ellipse, .diamond: return true
        default: return false
        }
    }

    var takesText: Bool {
        switch self {
        case .arrow, .line, .pen, .redact: return false
        default: return true
        }
    }
}

enum FillStyle: String, Codable, CaseIterable {
    case none
    case hachure
    case solid

    var label: String {
        switch self {
        case .none: return "None"
        case .hachure: return "Hachure"
        case .solid: return "Solid"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "square.dotted"
        case .hachure: return "line.diagonal"
        case .solid: return "square.fill"
        }
    }
}

enum CornerStyle: String, Codable, CaseIterable {
    case sharp
    case round

    var label: String { self == .sharp ? "Sharp" : "Round" }
    var symbol: String { self == .sharp ? "square" : "squircle" }
}

struct Block: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: BlockKind
    var parentID: UUID?
    /// Document coordinates, y-down.
    var rect: CGRect
    var text: String = ""
    /// Arbitrary colour as hex. Replaces the old five-index palette — those
    /// indices are now presets that write into this, not the range itself.
    var stroke: String = Palette.defaultStroke
    /// nil is no fill at all, which is different from white.
    var fill: String?
    var fillStyle: FillStyle = .solid
    var strokeWidth: Double = 2
    var cornerRadius: Double = 10
    var opacity: Double = 1
    /// Explicit text size. nil keeps the old behaviour — size derived from
    /// stroke weight — so a block only carries a number once someone has
    /// actually set one.
    var fontSize: Double?
    /// How far a connector bows out of its chord, as a signed fraction of the
    /// chord's length. Zero is a straight line; the sign picks a side.
    var curve: Double = 0
    /// Tilt onto a plane. nil is flat, which is what every block drawn before
    /// planes existed decodes to.
    var transform: Transform2D?
    /// Blocks sharing an id move and select as one. Separate from `parentID`,
    /// which is geometric nesting the export infers — grouping is a decision
    /// the person made, and it should survive them dragging things apart.
    var groupID: UUID?
    /// Stable per-block seed so roughness never shimmers between redraws.
    var seed: UInt64 = UInt64.random(in: 1...UInt64.max)
    /// Freehand points, `.pen` only. Document coordinates.
    var points: [CGPoint] = []
    var z: Int = 0

    init(id: UUID = UUID(), kind: BlockKind, parentID: UUID? = nil, rect: CGRect,
         text: String = "", stroke: String = Palette.defaultStroke, fill: String? = nil,
         fillStyle: FillStyle = .solid, strokeWidth: Double = 2,
         cornerRadius: Double = 10, opacity: Double = 1, fontSize: Double? = nil,
         curve: Double = 0, transform: Transform2D? = nil, groupID: UUID? = nil,
         seed: UInt64 = UInt64.random(in: 1...UInt64.max),
         points: [CGPoint] = [], z: Int = 0) {
        self.id = id
        self.kind = kind
        self.parentID = parentID
        self.rect = rect
        self.text = text
        self.stroke = stroke
        self.fill = fill
        self.fillStyle = fillStyle
        self.strokeWidth = strokeWidth
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.fontSize = fontSize
        self.curve = curve
        self.transform = transform
        self.groupID = groupID
        self.seed = seed
        self.points = points
        self.z = z
    }

    /// Hand-rolled so a scene saved by an older build still opens: every field
    /// added after v0.1 decodes to a default rather than failing the whole file.
    /// Includes the retired palette keys so old scenes can still be read.
    private enum CodingKeys: String, CodingKey {
        case id, kind, parentID, rect, text, stroke, fill, fillStyle
        case strokeWidth, cornerRadius, opacity, fontSize, curve, transform, groupID, seed, points, z
        case colorIndex, fillIndex, strokeIndex, corner
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(BlockKind.self, forKey: .kind) ?? .box
        parentID = try c.decodeIfPresent(UUID.self, forKey: .parentID)
        rect = try c.decodeIfPresent(CGRect.self, forKey: .rect) ?? .zero
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        fillStyle = try c.decodeIfPresent(FillStyle.self, forKey: .fillStyle) ?? .solid
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1

        // Migration. Scenes saved before colours went arbitrary carry palette
        // indices; read those and convert rather than dropping someone's
        // drawing on the floor.
        if let hex = try c.decodeIfPresent(String.self, forKey: .stroke) {
            stroke = HexColor.normalized(hex) ?? Palette.defaultStroke
        } else {
            let index = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
            stroke = Palette.strokePresets[max(0, min(Palette.strokePresets.count - 1, index))].hex
        }

        if c.contains(.fill) {
            let hex = try c.decodeIfPresent(String.self, forKey: .fill)
            fill = hex.flatMap { HexColor.normalized($0) }
        } else {
            let index = try c.decodeIfPresent(Int.self, forKey: .fillIndex) ?? 0
            // The old array reserved index 0 for "transparent"; the preset list
            // does not, so every legacy index shifts down by one.
            fill = index > 0 && index - 1 < Palette.fillPresets.count
                ? Palette.fillPresets[index - 1].hex
                : nil
        }

        if let width = try c.decodeIfPresent(Double.self, forKey: .strokeWidth) {
            strokeWidth = width
        } else {
            let index = try c.decodeIfPresent(Int.self, forKey: .strokeIndex) ?? 1
            strokeWidth = [1.1, 2.0, 3.4][max(0, min(2, index))]
        }

        if let radius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) {
            cornerRadius = radius
        } else {
            let corner = try c.decodeIfPresent(String.self, forKey: .corner) ?? "round"
            cornerRadius = corner == "sharp" ? 0 : 10
        }
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize)
        curve = try c.decodeIfPresent(Double.self, forKey: .curve) ?? 0
        transform = try c.decodeIfPresent(Transform2D.self, forKey: .transform)
        groupID = try c.decodeIfPresent(UUID.self, forKey: .groupID)
        seed = try c.decodeIfPresent(UInt64.self, forKey: .seed) ?? UInt64.random(in: 1...UInt64.max)
        points = try c.decodeIfPresent([CGPoint].self, forKey: .points) ?? []
        z = try c.decodeIfPresent(Int.self, forKey: .z) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(parentID, forKey: .parentID)
        try c.encode(rect, forKey: .rect)
        try c.encode(text, forKey: .text)
        try c.encode(stroke, forKey: .stroke)
        try c.encode(fill, forKey: .fill)
        try c.encode(fillStyle, forKey: .fillStyle)
        try c.encode(strokeWidth, forKey: .strokeWidth)
        try c.encode(cornerRadius, forKey: .cornerRadius)
        try c.encode(opacity, forKey: .opacity)
        try c.encodeIfPresent(fontSize, forKey: .fontSize)
        try c.encode(curve, forKey: .curve)
        // Only written once it is actually a tilt, so a flat scene's file does
        // not grow a field of zeroes on every block.
        try c.encodeIfPresent(transform?.isIdentity == true ? nil : transform, forKey: .transform)
        try c.encodeIfPresent(groupID, forKey: .groupID)
        try c.encode(seed, forKey: .seed)
        try c.encode(points, forKey: .points)
        try c.encode(z, forKey: .z)
    }

    /// Where a connector starts and ends.
    ///
    /// Read straight off the stored size rather than through `maxX`/`maxY`:
    /// those standardize, so a negative width collapsed the vector and an arrow
    /// could only ever point down and to the right. The sign of the size *is*
    /// the direction.
    var endpoints: (start: CGPoint, end: CGPoint) {
        (rect.origin, CGPoint(x: rect.origin.x + rect.size.width,
                              y: rect.origin.y + rect.size.height))
    }

    /// The quadratic control point that bows a connector off its chord.
    var curveControl: CGPoint {
        let (a, b) = endpoints
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        guard curve != 0 else { return mid }
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0.001 else { return mid }
        // Perpendicular to the chord, scaled by the bow. Doubled because a
        // quadratic passes through half the control point's offset.
        let nx = -dy / length, ny = dx / length
        let offset = CGFloat(curve) * length * 2
        return CGPoint(x: mid.x + nx * offset, y: mid.y + ny * offset)
    }

    /// The tilt actually in force. Reading this rather than `transform`
    /// directly means nothing downstream has to unwrap.
    var plane: Transform2D { transform ?? .identity }

    var isTilted: Bool { !(transform ?? .identity).isIdentity }

    /// The rect to hit-test and frame against.
    var bounds: CGRect {
        if kind == .pen, !points.isEmpty {
            let xs = points.map(\.x), ys = points.map(\.y)
            return CGRect(x: xs.min()!, y: ys.min()!,
                          width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
        // A tilted block occupies more than its rect, and selection chrome and
        // zoom-to-fit both need the space it really covers.
        if isTilted, !kind.isLinear, kind != .pen {
            return plane.bounds(of: rect.standardized)
        }
        if kind.isLinear {
            let (a, b) = endpoints
            var box = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                             width: abs(b.x - a.x), height: abs(b.y - a.y))
            if curve != 0 {
                // The bow leaves the chord, so the chord's box is not the shape's.
                let apex = curveApex
                box = box.union(CGRect(x: apex.x, y: apex.y, width: 0.001, height: 0.001))
            }
            return box
        }
        return rect.standardized
    }

    /// The furthest point of the bow from the chord — where the curve actually
    /// reaches, which is half way to the control point.
    var curveApex: CGPoint {
        let (a, b) = endpoints
        let c = curveControl
        return CGPoint(x: 0.25 * a.x + 0.5 * c.x + 0.25 * b.x,
                       y: 0.25 * a.y + 0.5 * c.y + 0.25 * b.y)
    }
}

extension CGRect {
    /// Translate without standardizing.
    ///
    /// `offsetBy` returns a standardized rect, which silently discards a
    /// negative width or height. For a connector that sign *is* the direction,
    /// so moving one would flip it end for end.
    func translated(dx: CGFloat, dy: CGFloat) -> CGRect {
        CGRect(x: origin.x + dx, y: origin.y + dy, width: size.width, height: size.height)
    }

    func safeInset(by d: CGFloat) -> CGRect {
        guard width > d * 2, height > d * 2 else { return self }
        return insetBy(dx: d, dy: d)
    }
}
