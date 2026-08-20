import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Control rather than Command: Cmd belongs to app shortcuts and Opt to
    /// special characters, so Ctrl is the least contested modifier on macOS.
    static let toggleCanvas = Self("toggleCanvas",
                                   default: .init(.space, modifiers: [.control, .option]))
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var controller: PanelController!
    private let store = SketchStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        controller = PanelController(store: store)
        PanelController.shared = controller

        buildStatusItem()

        KeyboardShortcuts.onKeyDown(for: .toggleCanvas) { [weak self] in
            self?.controller.toggle()
        }

        // First run opens the panel so the app isn't an invisible no-op.
        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            controller.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.save()
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.dashed.inset.filled",
                                          accessibilityDescription: "Blockpad")
        statusItem.button?.image?.isTemplate = true

        let menu = NSMenu()

        let toggle = NSMenuItem(title: "Show Blockpad", action: #selector(togglePanel), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let shortcutInfo = NSMenuItem(title: shortcutDescription(), action: nil, keyEquivalent: "")
        shortcutInfo.isEnabled = false
        menu.addItem(shortcutInfo)

        menu.addItem(.separator())

        let clear = NSMenuItem(title: "Clear Canvas", action: #selector(clearCanvas), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Blockpad", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func shortcutDescription() -> String {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .toggleCanvas) else {
            return "No shortcut set"
        }
        return "Toggle: \(shortcut.description)"
    }

    @objc private func togglePanel() { controller.toggle() }

    @objc private func clearCanvas() { CanvasHost.shared?.clearAll() }

    @objc private func quit() {
        store.save()
        NSApp.terminate(nil)
    }
}
