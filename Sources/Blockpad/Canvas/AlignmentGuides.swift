import CoreGraphics
import Foundation

/// A guide line to draw while dragging, in document coordinates.
struct AlignmentGuide: Equatable {
    let isVertical: Bool
    /// x for a vertical guide, y for a horizontal one.
    let position: CGFloat
    /// Extent along the other axis, so the line spans only the objects it relates.
    let start: CGFloat
    let end: CGFloat
}

/// Edge and centre alignment against the rest of the scene.
///
/// Grid snapping alone gets you tidy coordinates but not tidy *layouts* — two
/// boxes can both sit on the grid and still look misaligned by one step. This
/// compares the six interesting lines of the moving rect (three per axis)
/// against every other block and pulls to the nearest match.
enum Alignment {

    struct Result {
        var dx: CGFloat?
        var dy: CGFloat?
        var guides: [AlignmentGuide] = []
    }

    /// `tolerance` is in document units, so callers divide by zoom and the pull
    /// feels the same however far in you are.
    static func solve(moving: CGRect, others: [CGRect], tolerance: CGFloat) -> Result {
        guard !others.isEmpty else { return Result() }

        var result = Result()
        let movingX = [moving.minX, moving.midX, moving.maxX]
        let movingY = [moving.minY, moving.midY, moving.maxY]

        var bestX: (delta: CGFloat, position: CGFloat)?
        var bestY: (delta: CGFloat, position: CGFloat)?

        for other in others {
            for candidate in [other.minX, other.midX, other.maxX] {
                for value in movingX {
                    let delta = candidate - value
                    if abs(delta) <= tolerance, abs(delta) < abs(bestX?.delta ?? .greatestFiniteMagnitude) {
                        bestX = (delta, candidate)
                    }
                }
            }
            for candidate in [other.minY, other.midY, other.maxY] {
                for value in movingY {
                    let delta = candidate - value
                    if abs(delta) <= tolerance, abs(delta) < abs(bestY?.delta ?? .greatestFiniteMagnitude) {
                        bestY = (delta, candidate)
                    }
                }
            }
        }

        // Guides are collected after the winning offset is known, so every block
        // that ends up on the line gets a guide, not just the one that won.
        if let bestX {
            result.dx = bestX.delta
            let snapped = moving.offsetBy(dx: bestX.delta, dy: 0)
            let related = others.filter { other in
                [other.minX, other.midX, other.maxX].contains { abs($0 - bestX.position) < 0.5 }
            }
            if !related.isEmpty {
                let tops = related.map(\.minY) + [snapped.minY]
                let bottoms = related.map(\.maxY) + [snapped.maxY]
                result.guides.append(AlignmentGuide(isVertical: true,
                                                    position: bestX.position,
                                                    start: tops.min()!,
                                                    end: bottoms.max()!))
            }
        }

        if let bestY {
            result.dy = bestY.delta
            let snapped = moving.offsetBy(dx: 0, dy: bestY.delta)
            let related = others.filter { other in
                [other.minY, other.midY, other.maxY].contains { abs($0 - bestY.position) < 0.5 }
            }
            if !related.isEmpty {
                let lefts = related.map(\.minX) + [snapped.minX]
                let rights = related.map(\.maxX) + [snapped.maxX]
                result.guides.append(AlignmentGuide(isVertical: false,
                                                    position: bestY.position,
                                                    start: lefts.min()!,
                                                    end: rights.max()!))
            }
        }

        return result
    }
}
