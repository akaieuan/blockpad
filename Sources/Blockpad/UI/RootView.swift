import SwiftUI
import BlockpadKit

/// Layout breakpoints. The window is a floating utility that gets dragged small
/// constantly, so the chrome has to survive widths a normal app never sees.
private struct Layout {
    let width: CGFloat

    var compact: Bool { width < 860 }
    var showsActiveLabel: Bool { width >= 900 }
    var showsCopyLabel: Bool { width >= 700 }
    var toolSize: CGFloat { width >= 900 ? 33 : (width >= 780 ? 30 : 28) }
    var inspectorWidth: CGFloat { width >= 1000 ? 190 : 172 }
}

/// Chrome arrangement: tools sit in a dock along the bottom, not an island
/// across the top. The top edge of a drawing is where you look, so keeping it
/// clear is worth more than the conventional toolbar position — and it gives
/// the window a silhouette of its own rather than a borrowed one.
struct RootView: View {
    @ObservedObject var store: SketchStore
    @AppStorage("payloadMode") private var payloadModeRaw: String = PayloadMode.tree.rawValue

    var body: some View {
        GeometryReader { geometry in
            let layout = Layout(width: geometry.size.width)

            ZStack(alignment: .topLeading) {
                // Full-bleed canvas. All chrome floats above it rather than
                // partitioning the window, which is what made the old bar read
                // as a black stripe across the top.
                CanvasRepresentable(store: store,
                                    chromeInsets: NSEdgeInsets(
                                        top: 56,
                                        left: store.inspectorOpen ? layout.inspectorWidth + 40 : 78,
                                        bottom: 68,
                                        right: store.libraryOpen ? 290 : 24),
                                    onSend: send)
                    .ignoresSafeArea()

                // The top edge carries only the copy action; the traffic lights
                // own the other corner.
                HStack {
                    Spacer()
                    SendIsland(store: store,
                               showsLabel: layout.showsCopyLabel,
                               onSend: send)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                inspectorColumn(layout, availableRailHeight: geometry.size.height - 54 - 44 - 88)

                if store.libraryOpen {
                    HStack {
                        Spacer()
                        LibraryPanel(store: store,
                                     maxHeight: max(220, geometry.size.height - 150),
                                     canvas: { CanvasHost.shared })
                            .padding(.trailing, 12)
                            .padding(.top, 58)
                            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)))
                    }
                }

                VStack {
                    Spacer()
                    HStack(alignment: .bottom, spacing: 10) {
                        Spacer(minLength: 0)
                        ToolDock(store: store,
                                 buttonSize: layout.toolSize,
                                 showsActiveLabel: layout.showsActiveLabel)
                        Spacer(minLength: 0)
                        BottomControls(store: store, canvas: { CanvasHost.shared })
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

                if let toast = store.toast {
                    HStack {
                        Spacer()
                        Text(toast)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .glassSurface(cornerRadius: 9)
                        Spacer()
                    }
                    .padding(.top, 62)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            // Collapse on the way down, restore on the way back up. `initial`
            // matters: the panel restores a remembered frame after first layout,
            // so an onAppear check would decide against the wrong width.
            .onChange(of: layout.compact, initial: true) { _, isCompact in
                store.inspectorOpen = !isCompact
            }
        }
        .animation(.easeOut(duration: 0.16), value: store.toast)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: store.libraryOpen)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: store.inspectorOpen)
    }

    /// Sits under the traffic lights, which own the top-left corner.
    /// `availableRailHeight` is what stops the rail growing past the dock — it
    /// scrolls internally instead of spilling out of its own glass.
    @ViewBuilder
    private func inspectorColumn(_ layout: Layout, availableRailHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.inspectorOpen {
                PropertiesPanel(store: store,
                                width: layout.inspectorWidth,
                                maxHeight: max(180, availableRailHeight),
                                canvas: { CanvasHost.shared })
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
            HStack {
                ToolButton(symbol: store.inspectorOpen ? "sidebar.leading" : "slider.horizontal.3",
                           help: store.inspectorOpen ? "Hide properties" : "Show properties",
                           size: 28) {
                    store.inspectorOpen.toggle()
                }
                .padding(4)
                .glassSurface(cornerRadius: 11)
                Spacer()
            }
        }
        .padding(.leading, 12)
        .padding(.top, 54)
    }

    /// Puts the sketch into whatever you came from (§6).
    ///
    /// The payload always reaches the clipboard first, whatever happens next —
    /// every failure path below still leaves something you can paste by hand,
    /// which is what the toast promises.
    private func send() {
        guard !store.blocks.isEmpty else {
            store.flash("Nothing to copy")
            return
        }

        let mode = PayloadMode(rawValue: payloadModeRaw) ?? .tree
        // Captured when the panel opened, before it took key focus away from
        // whatever you were in. Reading it now would only ever find Blockpad.
        let target = PanelController.shared?.pendingTarget
        let strategy = AppAdapters().resolve(shape: mode.shape,
                                             bundleID: target?.bundleIdentifier)

        let tree = SketchExport.tree(store.blocks, template: store.template)
        var image: Data?
        var pathLine: String?

        if mode.shape.wantsImage {
            image = SketchExport.renderPNGData(store.blocks, options: store.renderOptions)
            // Terminals cannot take a pasted picture, so it goes to disk and the
            // path travels as text instead.
            if strategy == .pastePath, let png = image {
                pathLine = SketchFileWriter.write(png, forTargetPID: target?.processIdentifier)?.pasteText
            }
        }

        let payload = DeliveryPayload(text: mode.shape.wantsText ? tree : "",
                                      image: image,
                                      pathLine: pathLine)

        Deliverer.shared.deliver(payload: payload, to: target, strategy: strategy) { outcome in
            store.flash(outcome.message)
            // The panel is hidden by the time a post-activation failure is
            // known, so bring it back — otherwise the toast explaining what
            // went wrong is raised onto a window nobody can see.
            if !outcome.succeeded, outcome.panelWasHidden {
                PanelController.shared?.show()
            }
        }
    }
}

/// Bridges the AppKit canvas into the SwiftUI tree (§7).
struct CanvasRepresentable: NSViewRepresentable {
    let store: SketchStore
    var chromeInsets = NSEdgeInsets(top: 56, left: 24, bottom: 68, right: 24)
    let onSend: () -> Void

    func makeNSView(context: Context) -> CanvasView {
        let view = CanvasView(store: store)
        view.onSend = onSend
        view.chromeInsets = chromeInsets
        CanvasHost.shared = view
        return view
    }

    func updateNSView(_ view: CanvasView, context: Context) {
        view.onSend = onSend
        view.chromeInsets = chromeInsets
    }
}

/// The chrome reaches the canvas for operations that act on the selection. One
/// live canvas exists for the app's lifetime, so a reference is simpler and less
/// fragile than threading a binding through every panel.
@MainActor
enum CanvasHost {
    static weak var shared: CanvasView?
}
