import Foundation
import CoreGraphics

/// Connector geometry, kept out of the view so the direction rules can be tested.
///
/// The whole reason this exists: a connector's direction is the *sign* of its
/// stored width and height, and CGRect quietly throws that sign away. `maxX`,
/// `maxY`, `offsetBy` and `insetBy` all return standardized rects, so reading a
/// connector back through any of them collapses it into the down-right
/// quadrant. Everything here works from `origin` and `size` directly.
public enum Connector {

    /// Where the connector starts and ends, direction intact.
    public static func endpoints(of rect: CGRect) -> (start: CGPoint, end: CGPoint) {
        (rect.origin, CGPoint(x: rect.origin.x + rect.size.width,
                              y: rect.origin.y + rect.size.height))
    }

    /// The connector's heading in radians, measured from the positive x axis.
    public static func angle(of rect: CGRect) -> CGFloat {
        let (start, end) = endpoints(of: rect)
        return atan2(end.y - start.y, end.x - start.x)
    }

    public static func length(of rect: CGRect) -> CGFloat {
        let (start, end) = endpoints(of: rect)
        return hypot(end.x - start.x, end.y - start.y)
    }

    /// Rebuilds a connector from a heading and a length, keeping its start.
    public static func rect(from start: CGPoint, angle: CGFloat, length: CGFloat) -> CGRect {
        CGRect(x: start.x, y: start.y,
               width: cos(angle) * length, height: sin(angle) * length)
    }

    /// Translate without standardizing — the direction must survive a move.
    public static func translate(_ rect: CGRect, dx: CGFloat, dy: CGFloat) -> CGRect {
        CGRect(x: rect.origin.x + dx, y: rect.origin.y + dy,
               width: rect.size.width, height: rect.size.height)
    }

    /// Pulls `point` onto the nearest spoke around `anchor`, keeping its
    /// distance. 15° by default, which gives the eight compass points plus the
    /// half-steps between them.
    public static func snapToAngle(_ point: CGPoint, around anchor: CGPoint,
                                   step: CGFloat = .pi / 12) -> CGPoint {
        let heading = atan2(point.y - anchor.y, point.x - anchor.x)
        let snapped = (heading / step).rounded() * step
        let distance = hypot(point.x - anchor.x, point.y - anchor.y)
        return CGPoint(x: anchor.x + cos(snapped) * distance,
                       y: anchor.y + sin(snapped) * distance)
    }

    /// The quadratic control point that bows a connector off its chord by
    /// `curve`, a signed fraction of the chord's length.
    public static func control(of rect: CGRect, curve: Double) -> CGPoint {
        let (start, end) = endpoints(of: rect)
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        guard curve != 0 else { return mid }
        let dx = end.x - start.x, dy = end.y - start.y
        let span = hypot(dx, dy)
        guard span > 0.001 else { return mid }
        let nx = -dy / span, ny = dx / span
        let offset = CGFloat(curve) * span * 2
        return CGPoint(x: mid.x + nx * offset, y: mid.y + ny * offset)
    }

    /// A point along the bow, `t` from 0 at the start to 1 at the end.
    public static func point(on rect: CGRect, curve: Double, at t: CGFloat) -> CGPoint {
        let (start, end) = endpoints(of: rect)
        let c = control(of: rect, curve: curve)
        let u = 1 - t
        return CGPoint(x: u * u * start.x + 2 * u * t * c.x + t * t * end.x,
                       y: u * u * start.y + 2 * u * t * c.y + t * t * end.y)
    }
}
