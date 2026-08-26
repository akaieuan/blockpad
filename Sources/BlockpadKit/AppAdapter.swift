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

/// What the user asked to send, independent of what the target can take.
public enum PayloadShape: Sendable {
    case textOnly
    case imageOnly
    case textAndImage

    public var wantsImage: Bool { self != .textOnly }
    public var wantsText: Bool { self != .imageOnly }
}

extension AppAdapters {

    /// Reconciles what the user asked to send with what the target can receive.
    ///
    /// Two rules do the work. Text is safe to paste into anything, known app or
    /// not — it is exactly what Cmd+V would have done. An image is not: pasting
    /// one into an app that cannot take it produces either nothing or a blob of
    /// base64, so an unknown app carrying an image request degrades to the
    /// clipboard rather than guessing.
    public func resolve(shape: PayloadShape, bundleID: String?) -> DeliveryStrategy {
        let known = strategy(forBundleID: bundleID)

        guard shape.wantsImage else {
            // A known app that only takes text, an unknown app, or an image app
            // being sent text — all the same answer.
            return known == .manual ? .manual : .pasteText
        }

        switch known {
        case .some(let strategy) where strategy.carriesImage:
            return strategy
        case .some(.pasteText):
            // Known, but it cannot take a picture. Send what it can read.
            return .pasteText
        default:
            return .manual
        }
    }
}
