import Foundation

/// Which delivery strategy a given app needs.
///
/// Built-in adapters cover the apps people actually run agents in. Anything
/// else returns nil rather than guessing, because a wrong guess pastes a blob
/// of base64 or nothing at all into someone's editor — the user gets asked
/// once and the answer is remembered.
public struct AppAdapters: Sendable {

    public static let builtIn: [String: DeliveryStrategy] = [
        // Editors and desktop apps that accept a pasted image.
        "com.microsoft.VSCode": .pasteImage,
        "com.microsoft.VSCodeInsiders": .pasteImage,
        "com.todesktop.230313mzl4w4u92": .pasteImage,   // Cursor
        "dev.zed.Zed": .pasteImage,
        "com.anthropic.claudefordesktop": .pasteImage,
        "com.exafunction.windsurf": .pasteImage,
        "com.apple.dt.Xcode": .pasteImage,
        "com.apple.Safari": .pasteImage,
        "com.google.Chrome": .pasteImage,
        "company.thebrowser.Browser": .pasteImage,      // Arc

        // Terminals. These reject clipboard images, so they get a path.
        "com.apple.Terminal": .pastePath,
        "com.googlecode.iterm2": .pastePath,
        "com.mitchellh.ghostty": .pastePath,
        "dev.warp.Warp-Stable": .pastePath,
        "net.kovidgoyal.kitty": .pastePath,
        "io.alacritty": .pastePath,
        "co.zeit.hyper": .pastePath
    ]

    public private(set) var learned: [String: DeliveryStrategy]

    public init(learned: [String: DeliveryStrategy] = [:]) {
        self.learned = learned
    }

    /// nil means "no idea" — the caller should ask the user and then `learn`.
    public func strategy(forBundleID bundleID: String?) -> DeliveryStrategy? {
        guard let bundleID else { return nil }
        return learned[bundleID] ?? Self.builtIn[bundleID]
    }

    public mutating func learn(_ strategy: DeliveryStrategy, forBundleID bundleID: String) {
        learned[bundleID] = strategy
    }

    public mutating func forget(bundleID: String) {
        learned.removeValue(forKey: bundleID)
    }
}
