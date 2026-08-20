import AppKit
import Combine

enum Tool: Equatable {
    case select
    case draw(BlockKind)

    var kind: BlockKind? {
        if case .draw(let k) = self { return k }
        return nil
    }
}

struct SketchDocument: Codable {
    var blocks: [Block] = []
    var frameSize: CGSize?
    var pan: CGPoint = .zero
    var zoom: CGFloat = 1
}

/// Canvas contents persist across hide/show and across app restart (§2).
@MainActor
final class SketchStore: ObservableObject {
    @Published var blocks: [Block] = [] { didSet { scheduleSave() } }
    @Published var selection: Set<UUID> = []
    @Published var tool: Tool = .select
    @Published var colorIndex: Int = 0
    @Published var strokeIndex: Int = 1
    @Published var frameSize: CGSize? = FramePreset.all[0].size
    @Published var toast: String?

    /// Viewport, owned here so it survives hide/show too.
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

    // MARK: - Mutation

    func block(_ id: UUID) -> Block? { blocks.first { $0.id == id } }

    func replace(_ block: Block) {
        guard let i = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        blocks[i] = block
    }

    var nextZ: Int { (blocks.map(\.z).max() ?? 0) + 1 }

    /// Blocks in paint order. Frames sit under everything so they read as sheets.
    var sorted: [Block] {
        blocks.sorted { a, b in
            if (a.kind == .frame) != (b.kind == .frame) { return a.kind == .frame }
            return a.z < b.z
        }
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
        let doc = SketchDocument(blocks: blocks, frameSize: frameSize, pan: pan, zoom: zoom)
        do {
            let data = try JSONEncoder().encode(doc)
            try data.write(to: Self.storeURL, options: .atomic)
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
    }
}
