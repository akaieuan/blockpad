import AppKit
import BlockpadKit
import Combine

enum Tool: Equatable {
    case select
    case hand
    case eraser
    case draw(BlockKind)

    var kind: BlockKind? {
        if case .draw(let k) = self { return k }
        return nil
    }

    var isDrawing: Bool { kind != nil }
}

/// The style new blocks inherit, and what the properties panel edits.
struct Style: Equatable {
    var stroke: String = Palette.defaultStroke
    var fill: String?
    var fillStyle: FillStyle = .solid
    var strokeWidth: Double = 2
    var cornerRadius: Double = 10
    var opacity: Double = 1
    var fontSize: Double?
}

struct SketchDocument: Codable {
    var blocks: [Block] = []
    var frameSize: CGSize?
    var pan: CGPoint = .zero
    var zoom: CGFloat = 1
    var theme: String?
    var sketchy: Bool?
    var recentColors: [String]?
    var snapping: Bool?
    var template: String?
}

/// Canvas contents persist across hide/show and across app restart (§2).
@MainActor
final class SketchStore: ObservableObject {
    @Published var blocks: [Block] = [] { didSet { pruneSelection(); scheduleSave() } }
    @Published var selection: Set<UUID> = []
    @Published var tool: Tool = .select
    /// Excalidraw's padlock: when off, the tool reverts to select after one
    /// shape, which is what makes a fresh shape immediately draggable.
    @Published var toolLocked: Bool = false
    @Published var style = Style()
    @Published var frameSize: CGSize? = FramePreset.all[0].size
    @Published var theme: CanvasTheme = .paper { didSet { scheduleSave() } }
    /// Crisp is the default look; the hand-drawn renderer stays one toggle away.
    @Published var sketchy: Bool = false { didSet { scheduleSave() } }
    @Published var toast: String?
    @Published var libraryOpen: Bool = false
    @Published var inspectorOpen: Bool = true
    /// Alignment guides while dragging.
    @Published var snapping: Bool = true { didSet { scheduleSave() } }
    /// The active style template, by id. Sets defaults for new blocks and, for
    /// the one template with rules, checks what is already drawn.
    @Published var templateID: String? { didSet { scheduleSave() } }

    var template: StyleTemplate? { StyleTemplate.named(templateID) }

    /// What the active template flags, if it checks anything. Recomputed on
    /// read rather than cached — the scenes are small and a stale warning is
    /// worse than a recomputed one.
    var violations: [Violation] {
        guard let template, template.isChecked else { return [] }
        return template.violations(for: blocks.compactMap(ruleSubject))
    }

    /// Maps a block onto what the rules can judge. A block's stroke is also its
    /// label colour, and a label sits on the block's fill when it has one and on
    /// the paper when it does not.
    private func ruleSubject(_ block: Block) -> RuleSubject? {
        guard block.kind.takesText else { return nil }
        let bounds = block.bounds
        return RuleSubject(id: block.id,
                           foreground: block.stroke,
                           background: block.fill ?? theme.hex,
                           size: bounds.size,
                           fontSize: Double(BlockRenderer.fontSize(for: block)),
                           carriesLabel: !block.text.isEmpty,
                           couldBeControl: block.kind.takesFill)
    }

    /// Adopts a template's defaults for blocks drawn from now on. Never
    /// restyles what is already there — that is not a default, it is damage.
    func applyTemplate(_ template: StyleTemplate?) {
        templateID = template?.id
        guard let template else { return }
        let d = template.defaults
        style.stroke = d.stroke
        style.fill = d.fill
        style.strokeWidth = d.strokeWidth
        style.cornerRadius = d.cornerRadius
        style.fontSize = d.fontSize
        if let paper = d.paper, let match = CanvasTheme.all.first(where: { $0.name == paper }) {
            theme = match
        }
        flash("\(template.name)")
    }

    var renderOptions: RenderOptions { RenderOptions(theme: theme, sketchy: sketchy) }

    var pan: CGPoint = .zero { didSet { scheduleSave() } }
    var zoom: CGFloat = 1 { didSet { scheduleSave() } }

    private var saveWorkItem: DispatchWorkItem?
    private var toastWorkItem: DispatchWorkItem?

    static let storeURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Blockpad", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("scene.json")
    }()

    init() { load() }

    // MARK: - Access

    func block(_ id: UUID) -> Block? { blocks.first { $0.id == id } }

    /// Undo restores blocks but not the selection that went with them, so a
    /// selection can end up naming blocks that no longer exist. The inspector
    /// then shows Order and Edit rows that act on nothing. Drop the ghosts.
    private func pruneSelection() {
        guard !selection.isEmpty else { return }
        let live = Set(blocks.map(\.id))
        let kept = selection.intersection(live)
        guard kept.count != selection.count else { return }
        selection = kept
    }

    var selectedBlocks: [Block] { blocks.filter { selection.contains($0.id) } }

    var nextZ: Int { (blocks.map(\.z).max() ?? 0) + 1 }

    /// Paint order. Frames sit under everything so they read as sheets.
    var sorted: [Block] {
        blocks.sorted { a, b in
            if (a.kind == .frame) != (b.kind == .frame) { return a.kind == .frame }
            return a.z < b.z
        }
    }

    /// The style the panel should display: the selection's, when there is one.
    var effectiveStyle: Style {
        guard let first = selectedBlocks.first else { return style }
        return Style(stroke: first.stroke, fill: first.fill,
                     fillStyle: first.fillStyle, strokeWidth: first.strokeWidth,
                     cornerRadius: first.cornerRadius, opacity: first.opacity,
                     fontSize: first.fontSize)
    }

    /// Colours the user has actually reached for, newest first. Arbitrary
    /// colour is only usable if getting back to one you already picked is quick.
    @Published var recentColors: [String] = [] { didSet { scheduleSave() } }

    func noteRecent(_ hex: String) {
        guard let normalized = HexColor.normalized(hex) else { return }
        var next = recentColors.filter { $0 != normalized }
        next.insert(normalized, at: 0)
        recentColors = Array(next.prefix(12))
    }

    func flash(_ message: String) {
        toast = message
        toastWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func save() {
        let doc = SketchDocument(blocks: blocks, frameSize: frameSize,
                                 pan: pan, zoom: zoom, theme: theme.name, sketchy: sketchy,
                                 recentColors: recentColors, snapping: snapping,
                                 template: templateID)
        do {
            try JSONEncoder().encode(doc).write(to: Self.storeURL, options: .atomic)
        } catch {
            NSLog("Blockpad: save failed — \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.storeURL),
              let doc = try? JSONDecoder().decode(SketchDocument.self, from: data) else { return }
        blocks = doc.blocks
        frameSize = doc.frameSize
        pan = doc.pan
        zoom = doc.zoom == 0 ? 1 : doc.zoom
        theme = CanvasTheme.all.first { $0.name == doc.theme } ?? .paper
        sketchy = doc.sketchy ?? false
        snapping = doc.snapping ?? true
        recentColors = doc.recentColors ?? []
        templateID = doc.template
    }
}
