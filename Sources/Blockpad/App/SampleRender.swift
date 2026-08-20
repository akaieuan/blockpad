import AppKit

/// Headless render of a representative scene. A Mac app has no simulator, so
/// this is how the drawing can be inspected without a screen — and it doubles as
/// the fixture for open question #1 (tree-only vs tree+image).
enum SampleRender {
    static func run(outputDirectory: String) {
        let blocks = sampleScene()

        let dir = URL(fileURLWithPath: outputDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let pngURL = dir.appendingPathComponent("sample.png")
        if let data = SketchExport.renderPNGData(blocks, options: RenderOptions(), scale: 2) {
            try? data.write(to: pngURL)
            print("wrote \(pngURL.path)")
        } else {
            print("render failed")
        }

        let tree = SketchExport.tree(blocks)
        let treeURL = dir.appendingPathComponent("sample.tree.txt")
        try? tree.write(to: treeURL, atomically: true, encoding: .utf8)
        print("wrote \(treeURL.path)\n")
        print(tree)
    }

    /// The example from §5: a filters panel on the right of a desktop frame.
    static func sampleScene() -> [Block] {
        var blocks: [Block] = []
        var z = 0
        func add(_ kind: BlockKind, _ rect: CGRect, _ text: String = "",
                 color: Int = 0, fill: Int = 0, stroke: Int = 1, seed: UInt64) {
            z += 1
            blocks.append(Block(kind: kind, rect: rect, text: text, colorIndex: color,
                                fillIndex: fill, fillStyle: .solid, corner: .round,
                                strokeIndex: stroke, seed: seed, z: z))
        }

        add(.frame, CGRect(x: 0, y: 0, width: 1440, height: 900), "Desktop", seed: 11)
        add(.box, CGRect(x: 960, y: 0, width: 480, height: 900), "", color: 1, fill: 1, stroke: 2, seed: 22)
        add(.box, CGRect(x: 984, y: 32, width: 136, height: 40), "All", fill: 4, seed: 33)
        add(.box, CGRect(x: 1128, y: 32, width: 136, height: 40), "Active", seed: 44)
        add(.box, CGRect(x: 1272, y: 32, width: 136, height: 40), "Archived", seed: 55)

        for i in 0..<6 {
            let y = CGFloat(112 + i * 88)
            add(.box, CGRect(x: 984, y: y, width: 424, height: 64), "", seed: UInt64(100 + i))
            add(.box, CGRect(x: 1000, y: y + 20, width: 24, height: 24), "", color: 3, seed: UInt64(200 + i))
        }

        add(.box, CGRect(x: 984, y: 800, width: 200, height: 56), "Reset", color: 1, seed: 66)
        add(.box, CGRect(x: 1208, y: 800, width: 200, height: 56), "Apply", color: 2, fill: 2, stroke: 2, seed: 77)
        add(.text, CGRect(x: 40, y: 40, width: 400, height: 24),
            "main content unchanged", color: 1, seed: 88)
        add(.text, CGRect(x: 40, y: 76, width: 520, height: 24),
            "panel becomes bottom drawer under 768", color: 4, seed: 99)
        return blocks
    }
}
