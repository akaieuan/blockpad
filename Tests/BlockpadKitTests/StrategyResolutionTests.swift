import XCTest
@testable import BlockpadKit

/// Deciding what to send is where a wrong answer is expensive: an image pasted
/// into something that cannot take one produces base64 or silence.
final class StrategyResolutionTests: XCTestCase {

    private let adapters = AppAdapters()
    private let vscode = "com.microsoft.VSCode"
    private let ghostty = "com.mitchellh.ghostty"
    private let unknown = "com.example.SomethingNobodyMapped"

    // MARK: - Text goes anywhere

    func testTextPastesIntoAKnownEditor() {
        XCTAssertEqual(adapters.resolve(shape: .textOnly, bundleID: vscode), .pasteText)
    }

    func testTextPastesIntoATerminal() {
        XCTAssertEqual(adapters.resolve(shape: .textOnly, bundleID: ghostty), .pasteText)
    }

    /// The important one: text into an unmapped app is still a paste, because
    /// that is exactly what Cmd+V would have done anyway.
    func testTextPastesIntoAnUnknownApp() {
        XCTAssertEqual(adapters.resolve(shape: .textOnly, bundleID: unknown), .pasteText)
    }

    func testTextWithNoTargetAtAll() {
        XCTAssertEqual(adapters.resolve(shape: .textOnly, bundleID: nil), .pasteText)
    }

    // MARK: - Images are fussier

    func testImageGoesToTheClipboardForAnEditor() {
        XCTAssertEqual(adapters.resolve(shape: .imageOnly, bundleID: vscode), .pasteImage)
        XCTAssertEqual(adapters.resolve(shape: .textAndImage, bundleID: vscode), .pasteImage)
    }

    /// Terminals reject clipboard images, so the picture becomes a path.
    func testImageBecomesAPathForATerminal() {
        XCTAssertEqual(adapters.resolve(shape: .imageOnly, bundleID: ghostty), .pastePath)
        XCTAssertEqual(adapters.resolve(shape: .textAndImage, bundleID: ghostty), .pastePath)
    }

    /// An unknown app plus an image is the one case worth refusing.
    func testImageIntoAnUnknownAppFallsBackToTheClipboard() {
        XCTAssertEqual(adapters.resolve(shape: .imageOnly, bundleID: unknown), .manual)
        XCTAssertEqual(adapters.resolve(shape: .textAndImage, bundleID: nil), .manual)
    }

    /// A learned text-only app asked for an image sends the text instead of
    /// refusing — it can still read that.
    func testKnownTextOnlyAppDowngradesToText() {
        let learned = AppAdapters(learned: ["com.example.Notes": .pasteText])
        XCTAssertEqual(learned.resolve(shape: .textAndImage, bundleID: "com.example.Notes"), .pasteText)
    }

    /// An app the user explicitly marked "copy only" stays copy-only, whatever
    /// is being sent.
    func testManualIsHonouredForBothShapes() {
        let learned = AppAdapters(learned: ["com.example.Locked": .manual])
        XCTAssertEqual(learned.resolve(shape: .textOnly, bundleID: "com.example.Locked"), .manual)
        XCTAssertEqual(learned.resolve(shape: .imageOnly, bundleID: "com.example.Locked"), .manual)
    }

    /// A learned answer beats the built-in map, which is the point of learning.
    func testLearnedOverridesBuiltIn() {
        let learned = AppAdapters(learned: [ghostty: .pasteText])
        XCTAssertEqual(learned.resolve(shape: .textAndImage, bundleID: ghostty), .pasteText)
    }

    /// Every built-in adapter must resolve to something that can actually carry
    /// an image, or it should not be in the image list at all.
    func testEveryBuiltInHandlesAnImageRequestSensibly() {
        for (bundleID, strategy) in AppAdapters.builtIn {
            let resolved = adapters.resolve(shape: .textAndImage, bundleID: bundleID)
            XCTAssertEqual(resolved, strategy, "\(bundleID) resolved to \(resolved)")
            XCTAssertTrue(resolved.carriesImage, "\(bundleID) is mapped but cannot carry an image")
        }
    }
}
