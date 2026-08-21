import AppKit
import BlockpadKit

/// Writes the PNG somewhere the receiving agent can read it.
///
/// In-repo relative paths beat absolute temp paths: agents handle them far
/// better, and the sketch ends up versioned next to the code it produced (§6).
enum SketchFileWriter {

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
            return (url, url.path)
        } catch {
            NSLog("Blockpad: could not write sketch — \(error)")
            return nil
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
