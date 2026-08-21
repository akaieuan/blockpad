import Foundation

/// How a payload reaches a particular app.
///
/// The split exists because terminals reject clipboard images outright — which
/// is exactly where CLI coding agents live. Writing the PNG to disk and pasting
/// its path is the only thing that makes image payloads work for them at all.
public enum DeliveryStrategy: String, Codable, CaseIterable, Sendable {
    /// Tree as text, synthetic Cmd+V. Works everywhere.
    case pasteText
    /// Pasteboard image plus Cmd+V. Editors, Claude Desktop, browsers.
    case pasteImage
    /// PNG written to disk, its path pasted. Terminals.
    case pastePath
    /// Clipboard only, with a toast. Unknown apps and failures.
    case manual

    public var label: String {
        switch self {
        case .pasteText: return "Paste text"
        case .pasteImage: return "Paste image"
        case .pastePath: return "Paste file path"
        case .manual: return "Copy only"
        }
    }

    public var detail: String {
        switch self {
        case .pasteText: return "Tree as text. Works anywhere."
        case .pasteImage: return "Editors and browsers that accept pasted images."
        case .pastePath: return "Terminals, which reject clipboard images."
        case .manual: return "Leaves it on the clipboard for you to paste."
        }
    }

    /// Whether this strategy can deliver a picture at all. Governs what the
    /// payload mode is allowed to include.
    public var carriesImage: Bool {
        self == .pasteImage || self == .pastePath
    }
}
