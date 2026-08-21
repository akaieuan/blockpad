import AppKit
import ApplicationServices
// IsSecureEventInputEnabled still lives in Carbon; there is no modern equivalent.
import Carbon.HIToolbox

/// Accessibility permission, requested on first send and never at launch.
///
/// A permission wall at launch is the difference between 80% activation and
/// 30% (§8), and until you actually try to deliver something there is nothing
/// to justify the prompt with.
enum AccessibilityGate {

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt if not yet trusted. Returns trust as of right
    /// now — granting is asynchronous and happens in System Settings, so a
    /// false here is the normal first-run answer, not an error.
    @discardableResult
    static func requestIfNeeded() -> Bool {
        if isTrusted { return true }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Opens the exact settings pane. The system prompt's own button is easy to
    /// dismiss and the pane is hard to find again afterwards.
    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url { NSWorkspace.shared.open(url) }
    }

    /// True while any app has secure text entry enabled — a password field, or
    /// a terminal running sudo. Synthetic keystrokes are blocked entirely and
    /// silently in that state, so a send has to say so rather than report a
    /// success that did not happen.
    static var isSecureInputActive: Bool { IsSecureEventInputEnabled() }
}
