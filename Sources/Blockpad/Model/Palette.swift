import AppKit

/// Five stroke swatches, no picker (§3). Ink, slate, dusty red, sage, amber.
enum Palette {
    static let colors: [NSColor] = [
        NSColor(srgbRed: 0.169, green: 0.165, blue: 0.157, alpha: 1), // ink   #2B2A28
        NSColor(srgbRed: 0.333, green: 0.404, blue: 0.478, alpha: 1), // slate #55677A
        NSColor(srgbRed: 0.706, green: 0.325, blue: 0.290, alpha: 1), // dusty red #B4534A
        NSColor(srgbRed: 0.431, green: 0.545, blue: 0.416, alpha: 1), // sage  #6E8B6A
        NSColor(srgbRed: 0.753, green: 0.541, blue: 0.180, alpha: 1)  // amber #C08A2E
    ]

    static let names = ["Ink", "Slate", "Dusty red", "Sage", "Amber"]

    /// Fills are tints of the stroke hues so a filled shape still reads as one
    /// object. Index 0 is transparent.
    static let fills: [NSColor?] = [
        nil,
        NSColor(srgbRed: 0.898, green: 0.890, blue: 0.875, alpha: 1),
        NSColor(srgbRed: 0.965, green: 0.855, blue: 0.835, alpha: 1),
        NSColor(srgbRed: 0.867, green: 0.918, blue: 0.855, alpha: 1),
        NSColor(srgbRed: 0.855, green: 0.898, blue: 0.937, alpha: 1),
        NSColor(srgbRed: 0.980, green: 0.918, blue: 0.780, alpha: 1)
    ]

    static let fillNames = ["Transparent", "Stone", "Blush", "Sage", "Sky", "Sand"]

    static func color(_ index: Int) -> NSColor {
        colors[max(0, min(colors.count - 1, index))]
    }

    static func name(_ index: Int) -> String {
        names[max(0, min(names.count - 1, index))]
    }

    static func fill(_ index: Int) -> NSColor? {
        guard index > 0, index < fills.count else { return nil }
        return fills[index]
    }

    static let selection = NSColor(srgbRed: 0.353, green: 0.333, blue: 0.855, alpha: 1)
}

/// Canvas background, switchable (asked for directly, not in the original §4).
struct CanvasTheme: Identifiable, Hashable, Codable {
    var id: String { name }
    let name: String
    let background: RGBA
    let isDark: Bool

    var color: NSColor { background.nsColor }

    /// Grid and frame chrome have to invert on a dark ground or they vanish.
    var gridColor: NSColor {
        isDark ? NSColor(white: 1, alpha: 0.10) : NSColor(srgbRed: 0.169, green: 0.165, blue: 0.157, alpha: 0.07)
    }

    var sheetColor: NSColor {
        isDark ? NSColor(white: 1, alpha: 0.04) : NSColor(srgbRed: 0.996, green: 0.996, blue: 0.992, alpha: 1)
    }

    var frameStroke: NSColor {
        isDark ? NSColor(white: 1, alpha: 0.22) : NSColor(srgbRed: 0.169, green: 0.165, blue: 0.157, alpha: 0.28)
    }

    /// Ink is invisible on a dark ground, so it flips to a warm off-white.
    func inkAdjusted(_ color: NSColor, index: Int) -> NSColor {
        guard isDark, index == 0 else { return color }
        return NSColor(srgbRed: 0.933, green: 0.925, blue: 0.906, alpha: 1)
    }

    static let all: [CanvasTheme] = [
        CanvasTheme(name: "Paper", background: RGBA(0.980, 0.980, 0.973), isDark: false),
        CanvasTheme(name: "White", background: RGBA(1, 1, 1), isDark: false),
        CanvasTheme(name: "Warm", background: RGBA(0.961, 0.941, 0.906), isDark: false),
        CanvasTheme(name: "Cool", background: RGBA(0.937, 0.953, 0.969), isDark: false),
        CanvasTheme(name: "Slate", background: RGBA(0.114, 0.118, 0.129), isDark: true)
    ]

    static var paper: CanvasTheme { all[0] }
}

/// NSColor is not Codable, so themes persist as components.
struct RGBA: Hashable, Codable {
    var r: Double, g: Double, b: Double, a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

enum StrokeWeight {
    static let widths: [CGFloat] = [1.1, 2.0, 3.4]
    static let names = ["Thin", "Medium", "Bold"]

    static func width(_ index: Int) -> CGFloat {
        widths[max(0, min(widths.count - 1, index))]
    }
}

/// Reference frame presets (§3).
struct FramePreset: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let size: CGSize

    static let all: [FramePreset] = [
        FramePreset(name: "Desktop", size: CGSize(width: 1440, height: 900)),
        FramePreset(name: "Tablet", size: CGSize(width: 834, height: 1112)),
        FramePreset(name: "Mobile", size: CGSize(width: 390, height: 844))
    ]
}
