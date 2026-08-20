import SwiftUI

/// Layout breakpoints. The window is a floating utility that gets dragged small
/// constantly, so the chrome has to survive widths a normal app never sees.
private struct Layout {
    let width: CGFloat

    var compact: Bool { width < 860 }
    var showsActiveLabel: Bool { width >= 900 }
    var showsCopyLabel: Bool { width >= 700 }
    var toolSize: CGFloat { width >= 900 ? 33 : (width >= 780 ? 30 : 28) }
    var inspectorWidth: CGFloat { width >= 1000 ? 186 : 168 }
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
                CanvasRepresentable(store: store, onSend: send)
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

                inspectorColumn(layout)

                if store.libraryOpen {
                    HStack {
                        Spacer()
                        LibraryPanel(store: store, canvas: { CanvasHost.shared })
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
            // Collapse on the way down, restore on the way back up. onAppear
            // matters as much as onChange: the panel is usually restored at a
            // remembered size, so the first layout is the one that counts.
            .onAppear { store.inspectorOpen = !layout.compact }
            .onChange(of: layout.compact) { _, isCompact in
                store.inspectorOpen = !isCompact
            }
        }
        .animation(.easeOut(duration: 0.16), value: store.toast)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: store.libraryOpen)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: store.inspectorOpen)
    }

    /// Sits under the traffic lights, which own the top-left corner.
    @ViewBuilder
    private func inspectorColumn(_ layout: Layout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.inspectorOpen {
                PropertiesPanel(store: store,
                                width: layout.inspectorWidth,
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

    private func send() {
        let mode = PayloadMode(rawValue: payloadModeRaw) ?? .tree
        store.flash(SketchExport.copyToPasteboard(store.blocks, mode: mode, options: store.renderOptions))
    }
}

/// Bridges the AppKit canvas into the SwiftUI tree (§7).
struct CanvasRepresentable: NSViewRepresentable {
    let store: SketchStore
    let onSend: () -> Void

    func makeNSView(context: Context) -> CanvasView {
        let view = CanvasView(store: store)
        view.onSend = onSend
        CanvasHost.shared = view
        return view
    }

    func updateNSView(_ view: CanvasView, context: Context) {
        view.onSend = onSend
    }
}

/// The chrome reaches the canvas for operations that act on the selection. One
/// live canvas exists for the app's lifetime, so a reference is simpler and less
/// fragile than threading a binding through every panel.
@MainActor
enum CanvasHost {
    static weak var shared: CanvasView?
}
