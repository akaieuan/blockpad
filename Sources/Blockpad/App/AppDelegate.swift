import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Control rather than Command: Cmd belongs to app shortcuts and Opt to
    /// special characters, so Ctrl is the least contested modifier on macOS.
    static let toggleCanvas = Self("toggleCanvas",
                                   default: .init(.space, modifiers: [.control, .option]))

    /// macOS ships Ctrl+Opt+Space bound to "Select next source in Input menu",
    /// and a system binding wins. This second, uncontested chord means the app
    /// is reachable on a clean machine without a trip to System Settings.
    static let toggleCanvasAlt = Self("toggleCanvasAlt",
                                      default: .init(.b, modifiers: [.control, .option]))
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
        KeyboardShortcuts.onKeyDown(for: .toggleCanvasAlt) { [weak self] in
            self?.controller.toggle()
        }

        // First run opens the panel so the app isn't an invisible no-op.
        // --show forces it, which is what makes relaunching during development
        // useful rather than silent.
        if CommandLine.arguments.contains("--show")
            || !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
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

        // Temporary: verifies Accessibility trust and window-title reading
        // during M1 Task 4. Removed before M1 ships.
        let probe = NSMenuItem(title: "Debug: Probe Frontmost", action: #selector(probeFrontmost), keyEquivalent: "")
        probe.target = self
        menu.addItem(probe)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Blockpad", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func shortcutDescription() -> String {
        let shortcuts = [KeyboardShortcuts.getShortcut(for: .toggleCanvas),
                         KeyboardShortcuts.getShortcut(for: .toggleCanvasAlt)]
            .compactMap { $0?.description }
        return shortcuts.isEmpty ? "No shortcut set" : "Toggle: " + shortcuts.joined(separator: "  or  ")
    }

    @objc private func togglePanel() { controller.toggle() }

    @objc private func clearCanvas() { CanvasHost.shared?.clearAll() }

    @objc private func probeFrontmost() {
        AccessibilityGate.requestIfNeeded()
        guard let target = PanelController.shared?.pendingTarget else {
            NSLog("Blockpad probe: no pending target")
            return
        }
        let title = FrontmostWindow.title(forProcessID: target.processIdentifier)
        NSLog("Blockpad probe: trusted=%@ secureInput=%@ bundle=%@ title=%@",
              String(AccessibilityGate.isTrusted),
              String(AccessibilityGate.isSecureInputActive),
              target.bundleIdentifier ?? "nil",
              title ?? "nil")
    }

    @objc private func quit() {
        store.save()
        NSApp.terminate(nil)
    }
}
