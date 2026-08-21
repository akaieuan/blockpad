import XCTest
@testable import BlockpadKit

final class AppAdapterTests: XCTestCase {
    func testEditorsTakePastedImages() {
        let adapters = AppAdapters()
        XCTAssertEqual(adapters.strategy(forBundleID: "com.microsoft.VSCode"), .pasteImage)
        XCTAssertEqual(adapters.strategy(forBundleID: "dev.zed.Zed"), .pasteImage)
    }

    func testTerminalsGetAFilePathBecauseTheyRejectClipboardImages() {
        let adapters = AppAdapters()
        XCTAssertEqual(adapters.strategy(forBundleID: "com.apple.Terminal"), .pastePath)
        XCTAssertEqual(adapters.strategy(forBundleID: "com.googlecode.iterm2"), .pastePath)
        XCTAssertEqual(adapters.strategy(forBundleID: "com.mitchellh.ghostty"), .pastePath)
    }

    func testUnknownAppsReturnNilSoTheUserIsAsked() {
        let adapters = AppAdapters()
        XCTAssertNil(adapters.strategy(forBundleID: "com.example.unheardof"))
        XCTAssertNil(adapters.strategy(forBundleID: nil))
    }

    func testLearnedChoiceOverridesTheBuiltInAdapter() {
        var adapters = AppAdapters()
        adapters.learn(.pasteText, forBundleID: "com.microsoft.VSCode")
        XCTAssertEqual(adapters.strategy(forBundleID: "com.microsoft.VSCode"), .pasteText)
    }

    func testLearnedChoicesAreExposedForPersistence() {
        var adapters = AppAdapters()
        adapters.learn(.pastePath, forBundleID: "com.example.unheardof")
        XCTAssertEqual(adapters.learned, ["com.example.unheardof": .pastePath])
    }

    func testForgettingRestoresTheBuiltInAnswer() {
        var adapters = AppAdapters()
        adapters.learn(.pasteText, forBundleID: "com.microsoft.VSCode")
        adapters.forget(bundleID: "com.microsoft.VSCode")
        XCTAssertEqual(adapters.strategy(forBundleID: "com.microsoft.VSCode"), .pasteImage)
    }
}
