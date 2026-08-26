import AppKit
import BlockpadKit
import CoreGraphics

struct DeliveryPayload {
    var text: String
    var image: Data?
    /// Set for `.pastePath`: the text that stands in for the image.
    var pathLine: String?
}

/// Runs the send sequence from §6:
/// hide, activate the target, wait for activation, write the pasteboard,
/// post Cmd+V — and never Return.
@MainActor
final class Deliverer {

    /// One instance for the app's lifetime: it owns an activation observer that
    /// has to outlive the call that started it.
    static let shared = Deliverer()

    /// What happened, and what to say about it. The panel is hidden before the
    /// paste, so a toast raised afterwards would be invisible — the caller uses
    /// this to bring the panel back when something went wrong after the hide.
    struct Outcome {
        let succeeded: Bool
        let message: String
        /// True once the panel has been hidden, so the caller knows the toast
        /// needs the window back to be seen at all.
        let panelWasHidden: Bool
    }

    private let virtualKeyV: CGKeyCode = 0x09
    /// A ceiling that stops a wedged app hanging the send, not a timing
    /// assumption — the notification is what actually gates the paste.
    private let activationTimeout: TimeInterval = 1.2
    /// One runloop turn for the target to install its first responder. This is
    /// a guess, and the first thing to suspect if a paste lands in the wrong
    /// place.
    private let firstResponderCushion: TimeInterval = 0.03

    private var activationObserver: NSObjectProtocol?

    func deliver(payload: DeliveryPayload,
                 to target: NSRunningApplication?,
                 strategy: DeliveryStrategy,
                 completion: @escaping (Outcome) -> Void) {

        // Written first and unconditionally. Every failure below still leaves a
        // usable payload on the clipboard, which is the promise the toast makes.
        writePasteboard(payload, strategy: strategy)

        func bail(_ message: String) {
            completion(Outcome(succeeded: false, message: message, panelWasHidden: false))
        }

        guard strategy != .manual else {
            return bail("Copied — paste it yourself")
        }

        guard let target, !target.isTerminated else {
            return bail("Copied — no app to paste into")
        }

        guard AccessibilityGate.requestIfNeeded() else {
            return bail("Copied — grant Accessibility to auto-paste")
        }

        // Synthetic keystrokes are dropped silently while secure input is on,
        // so say so rather than claiming a paste that never happened.
        guard !AccessibilityGate.isSecureInputActive else {
            return bail("Copied — secure input is blocking auto-paste")
        }

        PanelController.shared?.hideForDelivery()

        awaitActivation(of: target) { [weak self] activated in
            guard let self else { return }
            guard activated else {
                completion(Outcome(succeeded: false,
                                   message: "Copied — \(target.localizedName ?? "the app") did not come forward",
                                   panelWasHidden: true))
                return
            }
            self.postPaste()
            completion(Outcome(succeeded: true,
                               message: self.successMessage(for: strategy, payload: payload),
                               panelWasHidden: true))
        }

        target.activate()
    }

    // MARK: - Pasteboard

    private func writePasteboard(_ payload: DeliveryPayload, strategy: DeliveryStrategy) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()

        switch strategy {
        case .pasteImage:
            if let image = payload.image { item.setData(image, forType: .png) }
            if !payload.text.isEmpty { item.setString(payload.text, forType: .string) }
        case .pastePath:
            // Terminals reject clipboard images, so the path travels as text.
            let combined = [payload.text, payload.pathLine]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            item.setString(combined, forType: .string)
        case .pasteText, .manual:
            item.setString(payload.text, forType: .string)
        }

        pasteboard.writeObjects([item])
    }

    // MARK: - Activation

    /// Gates on the real activation notification rather than a fixed sleep,
    /// which §9.2 flagged as a magic number that would be flaky under load.
    private func awaitActivation(of target: NSRunningApplication,
                                 completion: @escaping (Bool) -> Void) {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
            DispatchQueue.main.asyncAfter(deadline: .now() + firstResponderCushion) {
                completion(true)
            }
            return
        }

        var finished = false
        let centre = NSWorkspace.shared.notificationCenter

        activationObserver = centre.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] note in
                guard let self, !finished else { return }
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.processIdentifier == target.processIdentifier else { return }
                finished = true
                self.removeActivationObserver()
                DispatchQueue.main.asyncAfter(deadline: .now() + self.firstResponderCushion) {
                    completion(true)
                }
            }

        DispatchQueue.main.asyncAfter(deadline: .now() + activationTimeout) { [weak self] in
            guard !finished else { return }
            finished = true
            self?.removeActivationObserver()
            completion(false)
        }
    }

    private func removeActivationObserver() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    // MARK: - Synthetic paste

    /// Cmd+V, and deliberately not Return. The agent might be mid-plan or on a
    /// permission gate, and a stray submit costs more than it saves (§6).
    private func postPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents],
            state: .eventSuppressionStateSuppressionInterval)

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: false)
        else { return }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func successMessage(for strategy: DeliveryStrategy, payload: DeliveryPayload) -> String {
        switch strategy {
        case .pasteText:
            let lines = payload.text.split(separator: "\n").count
            return "Pasted · \(lines) line\(lines == 1 ? "" : "s")"
        case .pasteImage: return "Pasted image"
        case .pastePath: return "Pasted path"
        case .manual: return "Copied"
        }
    }
}
