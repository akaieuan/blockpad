import XCTest
@testable import BlockpadKit

final class ProjectResolverTests: XCTestCase {

    private let home = URL(fileURLWithPath: "/Users/someone")

    /// Filesystem is injected, so these never touch disk.
    private func resolver(realPaths: Set<String>, repos: Set<String>) -> ProjectResolver {
        ProjectResolver(
            homeDirectory: home,
            isDirectory: { realPaths.contains($0.path) },
            containsProjectMarker: { repos.contains($0.path) }
        )
    }

    func testBareProjectNameIsNotResolvable() {
        // VS Code and Cursor render "file — project". A bare name is not a
        // path, and resolving it would mean searching the filesystem, which
        // this deliberately refuses to do. Documents the limit.
        let subject = resolver(realPaths: ["/Users/someone/code/myapp"],
                               repos: ["/Users/someone/code/myapp"])
        XCTAssertNil(subject.projectRoot(fromWindowTitle: "ContentView.swift — myapp"))
    }

    func testResolvesATildePathFromATerminalTitle() {
        let subject = resolver(realPaths: ["/Users/someone/code/myapp"],
                               repos: ["/Users/someone/code/myapp"])
        let result = subject.projectRoot(fromWindowTitle: "~/code/myapp — -zsh")
        XCTAssertEqual(result?.path, "/Users/someone/code/myapp")
    }

    func testResolvesAnAbsolutePath() {
        let subject = resolver(realPaths: ["/Users/someone/code/myapp"],
                               repos: ["/Users/someone/code/myapp"])
        let result = subject.projectRoot(fromWindowTitle: "/Users/someone/code/myapp — fish")
        XCTAssertEqual(result?.path, "/Users/someone/code/myapp")
    }

    func testIgnoresADirectoryThatIsNotAProject() {
        let subject = resolver(realPaths: ["/Users/someone/Downloads"], repos: [])
        XCTAssertNil(subject.projectRoot(fromWindowTitle: "~/Downloads — -zsh"))
    }

    func testStripsTerminalDecorationBeforeResolving() {
        // Terminal.app appends the window size.
        let subject = resolver(realPaths: ["/Users/someone/code/myapp"],
                               repos: ["/Users/someone/code/myapp"])
        let result = subject.projectRoot(fromWindowTitle: "~/code/myapp — -zsh — 80×24")
        XCTAssertEqual(result?.path, "/Users/someone/code/myapp")
    }

    func testHandlesMissingAndEmptyTitles() {
        let subject = resolver(realPaths: [], repos: [])
        XCTAssertNil(subject.projectRoot(fromWindowTitle: nil))
        XCTAssertNil(subject.projectRoot(fromWindowTitle: ""))
        XCTAssertNil(subject.projectRoot(fromWindowTitle: "   "))
    }

    func testPrefersTheDeepestSegmentThatIsAProject() {
        let subject = resolver(
            realPaths: ["/Users/someone/code", "/Users/someone/code/myapp"],
            repos: ["/Users/someone/code", "/Users/someone/code/myapp"])
        let result = subject.projectRoot(fromWindowTitle: "~/code — ~/code/myapp — -zsh")
        XCTAssertEqual(result?.path, "/Users/someone/code/myapp")
    }

    func testDoesNotEscapeHomeViaRelativeSegments() {
        // A title is untrusted text from another process; it must not be able
        // to point the writer at an arbitrary directory.
        let subject = resolver(realPaths: ["/Users/someone/code/myapp"],
                               repos: ["/Users/someone/code/myapp"])
        XCTAssertNil(subject.projectRoot(fromWindowTitle: "~/../../etc — -zsh"))
    }
}
