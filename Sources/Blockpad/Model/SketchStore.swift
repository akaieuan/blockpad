import AppKit
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
    var colorIndex: Int = 0
    var fillIndex: Int = 0
    var fillStyle: FillStyle = .solid
    var corner: CornerStyle = .round
    var opacity: Double = 1
    var strokeIndex: Int = 1
}

struct SketchDocument: Codable {
    var blocks: [Block] = []
    var frameSize: CGSize?
    var pan: CGPoint = .zero
    var zoom: CGFloat = 1
    var theme: String?
    var sketchy: Bool?
}

/// Canvas contents persist across hide/show and across app restart (§2).
@MainActor
final class SketchStore: ObservableObject {
    @Published var blocks: [Block] = [] { didSet { scheduleSave() } }
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
        return Style(colorIndex: first.colorIndex, fillIndex: first.fillIndex,
                     fillStyle: first.fillStyle, corner: first.corner,
                     opacity: first.opacity, strokeIndex: first.strokeIndex)
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
                                 pan: pan, zoom: zoom, theme: theme.name, sketchy: sketchy)
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
    }
}
