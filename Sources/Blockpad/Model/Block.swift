import Foundation
import CoreGraphics

/// Semantic type of a block. The canvas draws these differently, and the tree
/// serializer (§5) reads the same enum, which is why serialization is nearly free.
enum BlockKind: String, Codable, CaseIterable {
    case frame
    case box
    case text
    case arrow
    case callout
    case pen
    case redact

    var label: String {
        switch self {
        case .frame: return "Frame"
        case .box: return "Box"
        case .text: return "Text"
        case .arrow: return "Arrow"
        case .callout: return "Callout"
        case .pen: return "Pen"
        case .redact: return "Redact"
        }
    }

    var symbol: String {
        switch self {
        case .frame: return "rectangle.dashed"
        case .box: return "rectangle"
        case .text: return "textformat"
        case .arrow: return "arrow.up.right"
        case .callout: return "bubble.left"
        case .pen: return "scribble"
        case .redact: return "rectangle.fill"
        }
    }

    /// Keyboard shortcut, shown in the dropdown so people graduate off it (§3).
    var shortcut: String {
        switch self {
        case .frame: return "F"
        case .box: return "B"
        case .text: return "T"
        case .arrow: return "A"
        case .callout: return "C"
        case .pen: return "P"
        case .redact: return "R"
        }
    }

    /// Shipped in M0. The rest are drawn in later milestones but the model
    /// carries them now so persistence never needs a migration.
    var isAvailable: Bool {
        switch self {
        case .frame, .box, .text: return true
        default: return false
        }
    }
}

struct Block: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: BlockKind
    var parentID: UUID?
    /// Document coordinates, y-down.
    var rect: CGRect
    var text: String = ""
    var colorIndex: Int = 0
    var strokeIndex: Int = 1
    /// Stable per-block seed so roughness never shimmers between redraws.
    var seed: UInt64 = UInt64.random(in: 1...UInt64.max)
    /// Freehand points, `.pen` only. Document coordinates.
    var points: [CGPoint] = []
    var z: Int = 0

    var normalized: Block {
        var copy = self
        copy.rect = rect.standardized
        return copy
    }
}

extension CGRect {
    /// Insets that still produce a sane rect when the receiver is tiny.
    func safeInset(by d: CGFloat) -> CGRect {
        guard width > d * 2, height > d * 2 else { return self }
        return insetBy(dx: d, dy: d)
    }
}
