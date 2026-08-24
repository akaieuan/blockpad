import Foundation
import CoreGraphics

/// The camera: how far in, and where the document origin sits in view space.
///
/// A view point is `document * zoom + pan`, which is exactly what the canvas
/// applies to its context, so this struct is the whole camera and nothing else.
public struct Viewport: Equatable {
    public var zoom: CGFloat
    public var pan: CGPoint

    public init(zoom: CGFloat, pan: CGPoint) {
        self.zoom = zoom
        self.pan = pan
    }

    public func viewPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * zoom + pan.x, y: p.y * zoom + pan.y)
    }

    public func viewRect(_ r: CGRect) -> CGRect {
        CGRect(origin: viewPoint(r.origin),
               size: CGSize(width: r.width * zoom, height: r.height * zoom))
    }
}

/// How much of the canvas the floating chrome is sitting on top of.
public struct ChromeInsets: Equatable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat

    public init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    /// The part of `bounds` nothing is covering. Never collapses below a
    /// workable size, so a very short window still gets a sane answer instead of
    /// a negative one.
    public func visibleRect(in bounds: CGRect, minimum: CGFloat = 80) -> CGRect {
        CGRect(x: bounds.minX + left,
               y: bounds.minY + top,
               width: max(minimum, bounds.width - left - right),
               height: max(minimum, bounds.height - top - bottom))
    }
}

extension Viewport {
    /// Frames `content` inside the part of the canvas the chrome is not covering.
    ///
    /// This lives here rather than on the view because the arithmetic is the
    /// part that can be wrong, and a view is a bad place to prove anything. Two
    /// deliberate choices: the fit targets the *visible* rect, so a drawing does
    /// not settle underneath the inspector rail or the dock; and it never scales
    /// past 1:1, because blowing one small box up to fill the window is
    /// disorienting rather than helpful.
    public static func fitting(_ content: CGRect?,
                               in bounds: CGRect,
                               insets: ChromeInsets,
                               padding: CGFloat = 40,
                               zoomRange: ClosedRange<CGFloat> = 0.1...8) -> Viewport {
        let visible = insets.visibleRect(in: bounds)

        // Nothing to fit: sit at 1:1 with the origin where a first shape lands
        // in clear space rather than under the chrome.
        guard let content, content.width > 0 || content.height > 0 else {
            return Viewport(zoom: min(max(1, zoomRange.lowerBound), zoomRange.upperBound),
                            pan: CGPoint(x: visible.midX, y: visible.midY))
        }

        let target = content.insetBy(dx: -padding, dy: -padding)
        let raw = min(visible.width / target.width, visible.height / target.height, 1)
        let zoom = min(max(raw, zoomRange.lowerBound), zoomRange.upperBound)

        return Viewport(
            zoom: zoom,
            pan: CGPoint(x: visible.midX - target.midX * zoom,
                         y: visible.midY - target.midY * zoom))
    }
}
