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
    var collections: [VariableCollection]?
    var mode: String?
    var paperVariableID: UUID?
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
    @Published var variablesOpen: Bool = false
    @Published var inspectorOpen: Bool = true
    /// Alignment guides while dragging.
    @Published var snapping: Bool = true { didSet { scheduleSave() } }
    /// The active style template, by id. Sets defaults for new blocks and, for
    /// the one template with rules, checks what is already drawn.
    @Published var templateID: String? { didSet { scheduleSave() } }

    var template: StyleTemplate? { StyleTemplate.named(templateID) }

    /// Named values, and which mode the canvas is showing.
    @Published var collections: [VariableCollection] = [] { didSet { scheduleSave() } }
    @Published var mode: String = "Default" { didSet { scheduleSave() } }
    /// The canvas background, optionally bound to a colour variable.
    ///
    /// Without this, switching to Dark restyles every block and leaves the page
    /// behind them light — which is not a dark theme, it is a broken one. The
    /// paper is not a block, so it cannot carry a normal binding; it gets its
    /// own.
    @Published var paperVariableID: UUID? { didSet { scheduleSave() } }

    /// The theme actually used to draw, with a bound paper resolved into it.
    ///
    /// Returning a real CanvasTheme rather than a bare colour means everything
    /// downstream keeps working untouched — including `inkAdjusted`, which flips
    /// near-black ink to off-white by luminance, so text stays legible on a dark
    /// paper without anyone binding it.
    var effectiveTheme: CanvasTheme { paperTheme(in: mode) }

    /// The paper as it stands in a given mode. Taking a mode rather than reading
    /// the current one is what lets the rule check ask about Dark while Light is
    /// on screen.
    func paperTheme(in mode: String) -> CanvasTheme {
        guard let id = paperVariableID,
              let value = VariableResolver.resolve(
                  VariableBinding(property: .fill, variableID: id),
                  in: collections, mode: mode),
              let hex = value.colourHex,
              let c = HexColor.components(hex) else { return theme }
        // Same relative-luminance test the contrast checker uses, so "is this
        // paper dark" is answered one way in the whole app.
        let luminance = HexColor.relativeLuminance(hex) ?? 1
        return CanvasTheme(name: theme.name,
                           background: RGBA(c.r, c.g, c.b, c.a),
                           isDark: luminance < 0.18)
    }

    /// Every mode any collection defines, in order, deduplicated. Drives the
    /// switcher, which is per-canvas rather than per-collection: switching to
    /// "Dark" should switch everything that has a Dark.
    var availableModes: [String] {
        var seen: Set<String> = []
        return collections.flatMap(\.modes).filter { seen.insert($0).inserted }
    }

    /// What the active template flags, if it checks anything. Recomputed on
    /// read rather than cached — the scenes are small and a stale warning is
    /// worse than a recomputed one.
    ///
    /// Every mode is checked, not just the one on screen. A palette that passes
    /// in Light and fails in Dark is the bug this is for, and it is invisible
    /// from the mode you happen to be looking at.
    var violations: [Violation] {
        guard let template, template.isChecked else { return [] }
        let modes = availableModes
        guard modes.count > 1 else {
            return template.violations(for: blocks.compactMap { ruleSubject($0, mode: mode) })
        }
        return template.violations(across: modes.map { name in
            (mode: name, subjects: blocks.compactMap { ruleSubject($0, mode: name) })
        })
    }

    /// Maps a block onto what the rules can judge, as it resolves in one mode.
    ///
    /// A block's stroke is also its label colour, and a label sits on the
    /// block's fill when it has one and on the paper when it does not.
    private func ruleSubject(_ raw: Block, mode: String) -> RuleSubject? {
        guard raw.kind.takesText else { return nil }
        // Judge what the mode shows, not what the block stores. A bound fill is
        // a different colour in every mode, which is the entire point.
        let block = BlockRenderer.resolved(raw, options: RenderOptions(
            theme: theme, sketchy: sketchy, collections: collections, mode: mode))
        let paper = paperTheme(in: mode)
        let bounds = block.bounds
        return RuleSubject(id: block.id,
                           foreground: renderedInk(block.stroke, on: paper,
                                                   hasFill: block.fill != nil),
                           background: block.fill ?? paper.hex,
                           size: bounds.size,
                           fontSize: Double(BlockRenderer.fontSize(for: block)),
                           carriesLabel: !block.text.isEmpty,
                           couldBeControl: block.kind.takesFill)
    }

    /// The ink actually drawn. On a dark paper the renderer flips near-black
    /// strokes to off-white, so checking the stored colour would report contrast
    /// failures that are not on the screen — and hide the ones that are.
    private func renderedInk(_ hex: String, on paper: CanvasTheme, hasFill: Bool) -> String {
        guard !hasFill else { return hex }
        guard let srgb = paper.inkAdjusted(Palette.color(hex)).usingColorSpace(.sRGB) else { return hex }
        return HexColor.string(r: srgb.redComponent, g: srgb.greenComponent, b: srgb.blueComponent)
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

    var renderOptions: RenderOptions {
        RenderOptions(theme: effectiveTheme, sketchy: sketchy,
                      collections: collections, mode: mode)
    }

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
                                 template: templateID,
                                 collections: collections.isEmpty ? nil : collections,
                                 mode: collections.isEmpty ? nil : mode,
                                 paperVariableID: paperVariableID)
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
        collections = doc.collections ?? []
        mode = doc.mode ?? collections.first?.defaultMode ?? "Default"
        paperVariableID = doc.paperVariableID
    }
}
