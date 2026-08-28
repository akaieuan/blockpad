import AppKit
import Combine
import SwiftUI

/// A nonactivating panel that still takes key focus, so you can draw and type
/// without the app stealing "frontmost" from your editor.
final class SketchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Built at launch, reused forever, never constructed on hotkey (§7).
@MainActor
final class PanelController {
    static var shared: PanelController?

    let store: SketchStore
    private(set) var panel: SketchPanel!

    /// Captured before the panel takes focus (§6). Unused until M1 wires
    /// delivery, but the capture point is the part that's easy to get wrong.
    private(set) var pendingTarget: NSRunningApplication?

    let deliverer = Deliverer()

    private var showStartedAt: CFAbsoluteTime = 0
    private var cancellables = Set<AnyCancellable>()

    init(store: SketchStore) {
        self.store = store
        buildPanel()
    }

    private func buildPanel() {
        let panel = SketchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Blockpad"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.minSize = NSSize(width: 640, height: 440)
        // The canvas paints its own ground edge to edge. Leaving the window
        // opaque with a stale colour is what produced the strip above the
        // toolbar in the first build.
        panel.isOpaque = false
        panel.backgroundColor = .clear

        // Toolbar chrome floats over the canvas, so the titlebar must not
        // reserve any layout space of its own.
        let hosting = NSHostingView(rootView: RootView(store: store))
        hosting.frame = panel.contentLayoutRect
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        // Remembers its size and position across launches (§2).
        panel.setFrameAutosaveName("BlockpadPanel")
        if panel.frame.width < 200 {
            panel.setContentSize(NSSize(width: 960, height: 640))
            panel.center()
        }

        self.panel = panel

        // The chrome follows the canvas, not the system. A light paper canvas
        // under dark-mode glass is exactly the black-bar problem the floating
        // islands were meant to solve.
        // Reading `effectiveTheme` rather than the published value, because a
        // paper bound to a variable is dark by mode rather than by name — and
        // light glass over a dark canvas is the same black-bar problem the
        // floating islands were meant to solve.
        Publishers.Merge4(store.$theme.map { _ in () },
                          store.$collections.map { _ in () },
                          store.$mode.map { _ in () },
                          store.$paperVariableID.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak panel, weak store] in
                guard let store else { return }
                panel?.appearance = NSAppearance(
                    named: store.effectiveTheme.isDark ? .darkAqua : .aqua)
            }
            .store(in: &cancellables)
    }

    // MARK: - Visibility

    var isVisible: Bool { panel.isVisible }

    /// Hotkey toggles visibility, it does not summon a fresh instance (§2).
    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        showStartedAt = CFAbsoluteTimeGetCurrent()

        // Store the frontmost app first: the panel is about to take key focus,
        // so afterwards we can no longer tell where we came from (§6).
        pendingTarget = NSWorkspace.shared.frontmostApplication

        panel.orderFrontRegardless()
        panel.makeKey()
        if let canvas = CanvasHost.shared {
            panel.makeFirstResponder(canvas)
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - showStartedAt) * 1000
        Metrics.lastShowMilliseconds = elapsed
        if elapsed > 200 {
            NSLog("Blockpad: show took %.1fms (budget 200ms)", elapsed)
        }
    }

    /// Esc hides, it does not discard (§2).
    func hide() {
        CanvasHost.shared?.commitEditor()
        store.save()
        panel.orderOut(nil)
        // Hand focus back where it came from so the loop stays where you were.
        pendingTarget?.activate()
    }

    /// Hides without re-activating the target. The deliverer owns activation
    /// during a send, and two activations racing each other is how a paste
    /// lands in the wrong window.
    func hideForDelivery() {
        CanvasHost.shared?.commitEditor()
        store.save()
        panel.orderOut(nil)
    }
}

enum Metrics {
    /// 200ms from keypress to first stroke is the product (§7).
    nonisolated(unsafe) static var lastShowMilliseconds: Double = 0
}
