import AppKit
import SwiftUI

/// Offscreen render of the floating chrome.
///
/// The canvas has had `--render-sample` since the beginning, for the plain
/// reason that a Mac app has no simulator. The chrome had nothing, so every
/// change to the inspector or a panel was checked by screenshotting a running
/// window — which stops working the moment screen recording is unavailable, and
/// which cannot show a state you have not clicked your way into.
///
/// The glass is a live `NSVisualEffectView` sampling a desktop that is not
/// there, so it renders flat. Layout, type, spacing and state are exactly what
/// the app draws.
@MainActor
enum ChromeRender {

    static func run(outputPath: String) {
        let store = SketchStore()

        // Three states worth seeing at once: a selection with its properties, the
        // canvas section, and the variables sheet.
        let selected = store.blocks.first { $0.bindings?.isEmpty == false && $0.kind.takesFill }
        let withSelection = SketchStore()
        withSelection.selection = selected.map { [$0.id] } ?? []

        let panels = HStack(alignment: .top, spacing: 24) {
            labelled("Selection") {
                PropertiesPanel(store: withSelection, width: 190, canvas: { nil })
            }
            labelled("Canvas") {
                PropertiesPanel(store: store, width: 190, canvas: { nil })
            }
            labelled("Variables") {
                VariablesPanel(store: store)
            }
            labelled("Bind") {
                BindPicker(model: bindModel(store), draft: .constant("brand"), dismiss: {})
                    .glassSurface(cornerRadius: Token.Radius.group)
            }
        }
        .padding(28)
        .background(Color(nsColor: NSColor(srgbRed: 0.42, green: 0.44, blue: 0.46, alpha: 1)))

        guard let image = snapshot(panels) else {
            print("chrome render failed"); return
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("chrome encode failed"); return
        }
        try? png.write(to: URL(fileURLWithPath: outputPath))
        print("wrote \(outputPath)  (\(store.variables.count) variables, "
            + "mode \(store.mode), \(store.violations.count) issues)")
        for violation in store.violations { print("  \(violation.message)") }
    }

    /// A stand-in for what the inspector builds when a fill row is bound, so the
    /// popover can be seen without being clicked open.
    private static func bindModel(_ store: SketchStore) -> BindGlyph.Model {
        BindGlyph.Model(symbol: "paintbrush",
                        property: .fill,
                        boundTo: store.variables.first { $0.name == "surface" }?.id,
                        candidates: store.candidates(for: .fill),
                        mode: store.mode,
                        value: .colour("#F97316"),
                        suggestedName: "brand",
                        onBind: { _ in },
                        onCreate: { _, _ in nil })
    }

    private static func labelled<Content: View>(_ title: String,
                                                @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            content()
        }
    }

    /// `ImageRenderer` flattens `NSViewRepresentable`, and the glass is one — so
    /// the view goes into a real window and the real hierarchy is cached.
    private static func snapshot<V: View>(_ view: V) -> NSImage? {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame,
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        window.setContentSize(hosting.fittingSize)
        window.layoutIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let image = NSImage(size: hosting.bounds.size)
        image.addRepresentation(rep)
        return image
    }
}
