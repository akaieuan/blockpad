import Foundation

/// Turns a window title into the project directory it refers to.
///
/// Editors and terminals both put the working context in their title, but in
/// different shapes: "file.swift — myapp", "~/code/myapp — -zsh",
/// "myapp — zsh — 80×24". This pulls out anything path-shaped, resolves it, and
/// only accepts it if the result actually looks like a project.
///
/// Filesystem access is injected so this stays a pure function under test.
public struct ProjectResolver: Sendable {

    /// What makes a directory a project rather than just a directory.
    public static let markers = [
        ".git", "Package.swift", "package.json", "Cargo.toml",
        "go.mod", "pyproject.toml", "Gemfile", "pom.xml", "build.gradle"
    ]

    private let homeDirectory: URL
    private let isDirectory: @Sendable (URL) -> Bool
    private let containsProjectMarker: @Sendable (URL) -> Bool

    public init(homeDirectory: URL,
                isDirectory: @escaping @Sendable (URL) -> Bool,
                containsProjectMarker: @escaping @Sendable (URL) -> Bool) {
        self.homeDirectory = homeDirectory
        self.isDirectory = isDirectory
        self.containsProjectMarker = containsProjectMarker
    }

    public func projectRoot(fromWindowTitle title: String?) -> URL? {
        guard let title, !title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        // Every app that puts context in its title separates with an em or en
        // dash, so this is the one split that works across all of them.
        let separators = CharacterSet(charactersIn: "—–")
        let segments = title
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Longest first, so "~/code/myapp" wins over "~/code".
        let candidates = segments
            .filter { $0.hasPrefix("~/") || $0.hasPrefix("/") }
            .sorted { $0.count > $1.count }

        for candidate in candidates {
            guard let url = expand(candidate) else { continue }
            if isDirectory(url), containsProjectMarker(url) { return url }
        }
        return nil
    }

    private func expand(_ path: String) -> URL? {
        // A window title is text supplied by another process, and the result of
        // this decides where a file gets written. Anything with a relative
        // segment in it is refused rather than normalised, because normalising
        // it would silently accept "~/../../etc".
        guard !path.contains("..") else { return nil }

        if path.hasPrefix("~/") {
            let suffix = String(path.dropFirst(2))
            return homeDirectory.appendingPathComponent(suffix)
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}

extension ProjectResolver {
    /// The real one, backed by FileManager.
    public static func live(fileManager: FileManager = .default) -> ProjectResolver {
        ProjectResolver(
            homeDirectory: fileManager.homeDirectoryForCurrentUser,
            isDirectory: { url in
                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                return exists && isDirectory.boolValue
            },
            containsProjectMarker: { url in
                ProjectResolver.markers.contains { marker in
                    FileManager.default.fileExists(atPath: url.appendingPathComponent(marker).path)
                }
            }
        )
    }
}
