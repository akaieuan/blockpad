import Foundation

/// One source of truth for the toolbar, the shortcuts and the tooltips, so a
/// tool can never appear in the bar without a key or vice versa.
struct ToolSpec: Identifiable {
    let id: String
    let tool: Tool
    let symbol: String
    let label: String
    /// Mnemonic letter, the way people actually learn a canvas app.
    let key: String
    /// Positional digit. Kept for the shortcut and the tooltip, but no longer
    /// stamped on the button — those badges were the single most identifying
    /// feature of the bar this one is trying not to look like.
    let digit: String
    /// Tools cluster by what they are for, and clusters get a separator.
    let group: Int

    static let all: [ToolSpec] = [
        ToolSpec(id: "select",  tool: .select,          symbol: "cursorarrow",       label: "Select",    key: "v", digit: "1", group: 0),
        ToolSpec(id: "hand",    tool: .hand,            symbol: "hand.raised",       label: "Pan",       key: "h", digit: "2", group: 0),
        ToolSpec(id: "frame",   tool: .draw(.frame),    symbol: "rectangle.dashed",  label: "Frame",     key: "f", digit: "3", group: 1),
        ToolSpec(id: "box",     tool: .draw(.box),      symbol: "square",            label: "Rectangle", key: "r", digit: "4", group: 1),
        ToolSpec(id: "ellipse", tool: .draw(.ellipse),  symbol: "circle",            label: "Ellipse",   key: "o", digit: "5", group: 1),
        ToolSpec(id: "diamond", tool: .draw(.diamond),  symbol: "diamond",           label: "Diamond",   key: "d", digit: "6", group: 1),
        ToolSpec(id: "arrow",   tool: .draw(.arrow),    symbol: "arrow.right",       label: "Arrow",     key: "a", digit: "7", group: 2),
        ToolSpec(id: "line",    tool: .draw(.line),     symbol: "line.diagonal",     label: "Line",      key: "l", digit: "8", group: 2),
        ToolSpec(id: "pen",     tool: .draw(.pen),      symbol: "scribble",          label: "Draw",      key: "p", digit: "9", group: 3),
        ToolSpec(id: "text",    tool: .draw(.text),     symbol: "character",         label: "Text",      key: "t", digit: "0", group: 3),
        ToolSpec(id: "eraser",  tool: .eraser,          symbol: "eraser",            label: "Eraser",    key: "e", digit: "",  group: 3)
    ]
}

extension ToolSpec {
    var groupName: String {
        switch group {
        case 1: return "shapes"
        case 2: return "connectors"
        default: return "tools"
        }
    }

    /// Collapsed into one dock slot each (§3: if it is not in the bar it does
    /// not exist — so the bar has to stay short enough to mean it).
    static var shapes: [ToolSpec] { all.filter { $0.group == 1 } }
    static var connectors: [ToolSpec] { all.filter { $0.group == 2 } }
}

enum Shortcuts {
    static func tool(for characters: String) -> Tool? {
        ToolSpec.all.first { $0.key == characters || (!$0.digit.isEmpty && $0.digit == characters) }?.tool
    }
}
