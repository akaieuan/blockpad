import AppKit

/// Five swatches, no picker (§3). Ink, slate, dusty red, sage, amber.
enum Palette {
    static let colors: [NSColor] = [
        NSColor(srgbRed: 0.169, green: 0.165, blue: 0.157, alpha: 1), // ink   #2B2A28
        NSColor(srgbRed: 0.333, green: 0.404, blue: 0.478, alpha: 1), // slate #55677A
        NSColor(srgbRed: 0.706, green: 0.325, blue: 0.290, alpha: 1), // dusty red #B4534A
        NSColor(srgbRed: 0.431, green: 0.545, blue: 0.416, alpha: 1), // sage  #6E8B6A
        NSColor(srgbRed: 0.753, green: 0.541, blue: 0.180, alpha: 1)  // amber #C08A2E
    ]

    static let names = ["Ink", "Slate", "Dusty red", "Sage", "Amber"]

    static func color(_ index: Int) -> NSColor {
        colors[max(0, min(colors.count - 1, index))]
    }

    static func name(_ index: Int) -> String {
        names[max(0, min(names.count - 1, index))]
    }

    /// Paper, not white (§4).
    static let paper = NSColor(srgbRed: 0.980, green: 0.980, blue: 0.973, alpha: 1)
    /// Frames read as sheets on a desk, so they sit slightly brighter than the desk.
    static let sheet = NSColor(srgbRed: 0.996, green: 0.996, blue: 0.992, alpha: 1)
    static let grid = NSColor(srgbRed: 0.169, green: 0.165, blue: 0.157, alpha: 0.06)
    static let selection = NSColor(srgbRed: 0.239, green: 0.478, blue: 0.898, alpha: 1)
}

enum StrokeWeight {
    static let widths: [CGFloat] = [1.1, 1.9, 3.2]
    static let names = ["Thin", "Medium", "Thick"]

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
        FramePreset(name: "Mobile", size: CGSize(width: 390, height: 844))
    ]
}
