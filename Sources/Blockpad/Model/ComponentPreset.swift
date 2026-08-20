import CoreGraphics
import Foundation

/// Five shapes that happen to look like common patterns, not a component
/// library (§3). Each preset is plain blocks the moment it lands, so there is
/// nothing special to select, resize or serialize.
struct ComponentPreset: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let size: CGSize
    let parts: [Part]

    struct Part {
        let kind: BlockKind
        /// Relative to the preset's origin.
        let rect: CGRect
        var text: String = ""
        var fill: Int = 0
        var color: Int = 0
        var stroke: Int? = nil
    }

    func build(at origin: CGPoint, style: Style) -> [Block] {
        parts.map { part in
            Block(kind: part.kind,
                  rect: part.rect.offsetBy(dx: origin.x, dy: origin.y),
                  text: part.text,
                  colorIndex: part.color,
                  fillIndex: part.kind.takesFill ? part.fill : 0,
                  fillStyle: part.fill == 0 ? .none : style.fillStyle,
                  corner: style.corner,
                  opacity: 1,
                  strokeIndex: part.stroke ?? style.strokeIndex)
        }
    }

    // MARK: - Library

    static let all: [ComponentPreset] = [card, dialog, sidebar, navbar, table, form, tabs, listRows]

    static let card = ComponentPreset(
        id: "card", name: "Card", symbol: "rectangle.portrait", size: CGSize(width: 260, height: 200),
        parts: [
            Part(kind: .box, rect: CGRect(x: 0, y: 0, width: 260, height: 200)),
            Part(kind: .box, rect: CGRect(x: 16, y: 16, width: 228, height: 96), fill: 1, color: 1),
            Part(kind: .text, rect: CGRect(x: 16, y: 126, width: 180, height: 20), text: "Title"),
            Part(kind: .text, rect: CGRect(x: 16, y: 152, width: 200, height: 18), text: "Supporting copy", color: 1)
        ])

    static let dialog = ComponentPreset(
        id: "dialog", name: "Dialog", symbol: "macwindow", size: CGSize(width: 380, height: 220),
        parts: [
            Part(kind: .box, rect: CGRect(x: 0, y: 0, width: 380, height: 220)),
            Part(kind: .text, rect: CGRect(x: 20, y: 22, width: 240, height: 22), text: "Are you sure?"),
            Part(kind: .text, rect: CGRect(x: 20, y: 54, width: 300, height: 18),
                 text: "This cannot be undone.", color: 1),
            Part(kind: .box, rect: CGRect(x: 148, y: 156, width: 100, height: 40), text: "Cancel", color: 1),
            Part(kind: .box, rect: CGRect(x: 260, y: 156, width: 100, height: 40), text: "Delete", fill: 2, color: 2)
        ])

    static let sidebar = ComponentPreset(
        id: "sidebar", name: "Sidebar", symbol: "sidebar.left", size: CGSize(width: 520, height: 340),
        parts: [
            Part(kind: .box, rect: CGRect(x: 0, y: 0, width: 520, height: 340)),
            Part(kind: .box, rect: CGRect(x: 0, y: 0, width: 160, height: 340), fill: 1, color: 1),
            Part(kind: .box, rect: CGRect(x: 16, y: 24, width: 128, height: 28), text: "Nav", color: 1),
            Part(kind: .box, rect: CGRect(x: 16, y: 64, width: 128, height: 28), color: 1),
            Part(kind: .box, rect: CGRect(x: 16, y: 104, width: 128, height: 28), color: 1),
            Part(kind: .text, rect: CGRect(x: 192, y: 28, width: 200, height: 22), text: "Content")
        ])

    static let navbar = ComponentPreset(
        id: "navbar", name: "Nav bar", symbol: "menubar.rectangle", size: CGSize(width: 560, height: 56),
        parts: [
            Part(kind: .box, rect: CGRect(x: 0, y: 0, width: 560, height: 56)),
            Part(kind: .ellipse, rect: CGRect(x: 16, y: 14, width: 28, height: 28), fill: 1, color: 1),
            Part(kind: .text, rect: CGRect(x: 60, y: 19, width: 120, height: 18), text: "Product"),
            Part(kind: .text, rect: CGRect(x: 300, y: 19, width: 60, height: 18), text: "Docs", color: 1),
            Part(kind: .text, rect: CGRect(x: 376, y: 19, width: 70, height: 18), text: "Pricing", color: 1),
            Part(kind: .box, rect: CGRect(x: 460, y: 12, width: 84, height: 32), text: "Sign in", fill: 4, color: 1)
        ])

    static let table = ComponentPreset(
        id: "table", name: "Table", symbol: "tablecells", size: CGSize(width: 460, height: 260),
        parts: {
            var parts = [Part(kind: .box, rect: CGRect(x: 0, y: 0, width: 460, height: 260)),
                         Part(kind: .box, rect: CGRect(x: 0, y: 0, width: 460, height: 44),
                              text: "Name          Status          Date", fill: 1, color: 1)]
            for row in 0..<4 {
                parts.append(Part(kind: .box,
                                  rect: CGRect(x: 0, y: 44 + CGFloat(row) * 54, width: 460, height: 54),
                                  color: 1))
            }
            return parts
        }())

    static let form = ComponentPreset(
        id: "form", name: "Form", symbol: "list.bullet.rectangle", size: CGSize(width: 320, height: 280),
        parts: [
            Part(kind: .text, rect: CGRect(x: 0, y: 0, width: 160, height: 20), text: "Email", color: 1),
            Part(kind: .box, rect: CGRect(x: 0, y: 26, width: 320, height: 44)),
            Part(kind: .text, rect: CGRect(x: 0, y: 90, width: 160, height: 20), text: "Password", color: 1),
            Part(kind: .box, rect: CGRect(x: 0, y: 116, width: 320, height: 44)),
            Part(kind: .box, rect: CGRect(x: 0, y: 186, width: 24, height: 24), color: 3),
            Part(kind: .text, rect: CGRect(x: 36, y: 190, width: 200, height: 18), text: "Remember me", color: 1),
            Part(kind: .box, rect: CGRect(x: 0, y: 234, width: 320, height: 46), text: "Continue", fill: 4)
        ])

    static let tabs = ComponentPreset(
        id: "tabs", name: "Tabs", symbol: "square.grid.3x1.below.line.grid.1x2", size: CGSize(width: 420, height: 44),
        parts: [
            Part(kind: .box, rect: CGRect(x: 0, y: 0, width: 140, height: 44), text: "All", fill: 1),
            Part(kind: .box, rect: CGRect(x: 140, y: 0, width: 140, height: 44), text: "Active", color: 1),
            Part(kind: .box, rect: CGRect(x: 280, y: 0, width: 140, height: 44), text: "Archived", color: 1)
        ])

    static let listRows = ComponentPreset(
        id: "list", name: "List", symbol: "list.bullet", size: CGSize(width: 420, height: 288),
        parts: {
            var parts: [Part] = []
            for row in 0..<4 {
                let y = CGFloat(row) * 72
                parts.append(Part(kind: .box, rect: CGRect(x: 0, y: y, width: 420, height: 64)))
                parts.append(Part(kind: .box, rect: CGRect(x: 16, y: y + 20, width: 24, height: 24), color: 3))
                parts.append(Part(kind: .text, rect: CGRect(x: 56, y: y + 23, width: 180, height: 18),
                                  text: "Item", color: 1))
            }
            return parts
        }())
}
