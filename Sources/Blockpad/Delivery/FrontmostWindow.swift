import ApplicationServices

/// Reads the focused window title of another process.
///
/// Requires Accessibility trust; returns nil without it rather than failing, so
/// a missing permission degrades to "write to the temp directory" instead of
/// breaking the send.
enum FrontmostWindow {

    static func title(forProcessID pid: pid_t) -> String? {
        guard AccessibilityGate.isTrusted else { return nil }

        let app = AXUIElementCreateApplication(pid)

        var windowValue: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(
            app, kAXFocusedWindowAttribute as CFString, &windowValue)
        guard windowResult == .success, let windowValue else { return nil }

        // Checked rather than forced: the attribute is only an AXUIElement when
        // the app actually has a focused window.
        guard CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { return nil }
        let window = unsafeBitCast(windowValue, to: AXUIElement.self)

        var titleValue: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(
            window, kAXTitleAttribute as CFString, &titleValue)
        guard titleResult == .success else { return nil }
        return titleValue as? String
    }
}
