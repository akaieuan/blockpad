import AppKit
import BlockpadKit

/// Writes the PNG somewhere the receiving agent can read it.
///
/// In-repo relative paths beat absolute temp paths: agents handle them far
/// better, and the sketch ends up versioned next to the code it produced (§6).
enum SketchFileWriter {

    /// How many sketches to keep in a project's .blockpad/ directory.
    ///
    /// Not one file overwritten every time: an agent can scroll back and re-read
    /// a path from an earlier message, and it would silently get the newest
    /// image while the surrounding text describes an older one. Keeping a short
    /// history makes stale references stay correct for as long as they plausibly
    /// matter, without the directory growing without limit.
    private static let keepCount = 5

    /// Returns the file it wrote and the text that should be pasted to refer
    /// to it — relative inside a project, absolute in the temp fallback.
    static func write(_ png: Data, forTargetPID pid: pid_t?) -> (url: URL, pasteText: String)? {
        let filename = "sketch-\(timestamp()).png"

        if let pid,
           let title = FrontmostWindow.title(forProcessID: pid),
           let root = ProjectResolver.live().projectRoot(fromWindowTitle: title) {
            let directory = root.appendingPathComponent(".blockpad", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent(filename)
                try png.write(to: url, options: .atomic)
                prune(directory)
                return (url, ".blockpad/\(filename)")
            } catch {
                // Read-only checkout, permissions, anything — fall through to
                // temp rather than failing the send over where a file landed.
                NSLog("Blockpad: could not write into project — \(error)")
            }
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Blockpad", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(filename)
            try png.write(to: url, options: .atomic)
            prune(directory)
            return (url, url.path)
        } catch {
            NSLog("Blockpad: could not write sketch — \(error)")
            return nil
        }
    }

    /// Deletes all but the newest `keepCount` sketches. Filenames are
    /// timestamped and sortable, so this is a name sort rather than a stat call
    /// per file — and it only ever removes files matching our own pattern, so a
    /// directory someone else uses cannot be damaged by it.
    private static func prune(_ directory: URL) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        let ours = names
            .filter { $0.hasPrefix("sketch-") && $0.hasSuffix(".png") }
            .sorted()
        guard ours.count > keepCount else { return }
        for name in ours.dropLast(keepCount) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// Sortable, and no characters that would need quoting in a shell.
    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}
