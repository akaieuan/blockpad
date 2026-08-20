import Foundation
import CoreGraphics

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
    var colorIndex: Int = 0
    var fillIndex: Int = 0
    var fillStyle: FillStyle = .hachure
    var corner: CornerStyle = .round
    var opacity: Double = 1
    var strokeIndex: Int = 1
    /// Stable per-block seed so roughness never shimmers between redraws.
    var seed: UInt64 = UInt64.random(in: 1...UInt64.max)
    /// Freehand points, `.pen` only. Document coordinates.
    var points: [CGPoint] = []
    var z: Int = 0

    init(id: UUID = UUID(), kind: BlockKind, parentID: UUID? = nil, rect: CGRect,
         text: String = "", colorIndex: Int = 0, fillIndex: Int = 0,
         fillStyle: FillStyle = .hachure, corner: CornerStyle = .round,
         opacity: Double = 1, strokeIndex: Int = 1,
         seed: UInt64 = UInt64.random(in: 1...UInt64.max),
         points: [CGPoint] = [], z: Int = 0) {
        self.id = id
        self.kind = kind
        self.parentID = parentID
        self.rect = rect
        self.text = text
        self.colorIndex = colorIndex
        self.fillIndex = fillIndex
        self.fillStyle = fillStyle
        self.corner = corner
        self.opacity = opacity
        self.strokeIndex = strokeIndex
        self.seed = seed
        self.points = points
        self.z = z
    }

    /// Hand-rolled so a scene saved by an older build still opens: every field
    /// added after v0.1 decodes to a default rather than failing the whole file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(BlockKind.self, forKey: .kind) ?? .box
        parentID = try c.decodeIfPresent(UUID.self, forKey: .parentID)
        rect = try c.decodeIfPresent(CGRect.self, forKey: .rect) ?? .zero
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        fillIndex = try c.decodeIfPresent(Int.self, forKey: .fillIndex) ?? 0
        fillStyle = try c.decodeIfPresent(FillStyle.self, forKey: .fillStyle) ?? .hachure
        corner = try c.decodeIfPresent(CornerStyle.self, forKey: .corner) ?? .round
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        strokeIndex = try c.decodeIfPresent(Int.self, forKey: .strokeIndex) ?? 1
        seed = try c.decodeIfPresent(UInt64.self, forKey: .seed) ?? UInt64.random(in: 1...UInt64.max)
        points = try c.decodeIfPresent([CGPoint].self, forKey: .points) ?? []
        z = try c.decodeIfPresent(Int.self, forKey: .z) ?? 0
    }

    /// The rect to hit-test and frame against. Linear shapes keep their vector.
    var bounds: CGRect {
        if kind == .pen, !points.isEmpty {
            let xs = points.map(\.x), ys = points.map(\.y)
            return CGRect(x: xs.min()!, y: ys.min()!,
                          width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
        return rect.standardized
    }
}

extension CGRect {
    func safeInset(by d: CGFloat) -> CGRect {
        guard width > d * 2, height > d * 2 else { return self }
        return insetBy(dx: d, dy: d)
    }
}
