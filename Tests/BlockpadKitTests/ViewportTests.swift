import XCTest
import CoreGraphics
@testable import BlockpadKit

/// The window Blockpad actually opens at, with the inspector rail on the left
/// and the tool dock along the bottom.
private let window = CGRect(x: 0, y: 0, width: 1025, height: 627)
private let chrome = ChromeInsets(top: 56, left: 230, bottom: 68, right: 24)

final class ViewportTests: XCTestCase {

    /// The whole point of the button: after a fit, the drawing is inside the
    /// space the chrome is not covering — not underneath the rail or the dock.
    func testFitLandsClearOfTheChrome() {
        let drawing = CGRect(x: 264, y: -600, width: 2400, height: 1160)
        let viewport = Viewport.fitting(drawing, in: window, insets: chrome)
        let onScreen = viewport.viewRect(drawing)
        let visible = chrome.visibleRect(in: window)

        XCTAssertGreaterThanOrEqual(onScreen.minX, visible.minX)
        XCTAssertGreaterThanOrEqual(onScreen.minY, visible.minY)
        XCTAssertLessThanOrEqual(onScreen.maxX, visible.maxX)
        XCTAssertLessThanOrEqual(onScreen.maxY, visible.maxY)
    }

    /// Centred in the visible rect, not in the window — otherwise a drawing
    /// looks off to one side exactly when the rail is open.
    func testFitCentresInTheVisibleRect() {
        let drawing = CGRect(x: 264, y: -600, width: 2400, height: 1160)
        let viewport = Viewport.fitting(drawing, in: window, insets: chrome)
        let onScreen = viewport.viewRect(drawing)
        let visible = chrome.visibleRect(in: window)

        XCTAssertEqual(onScreen.midX, visible.midX, accuracy: 0.5)
        XCTAssertEqual(onScreen.midY, visible.midY, accuracy: 0.5)
    }

    /// A tall drawing is limited by height, a wide one by width. Getting this
    /// backwards is the classic way a fit overflows one axis.
    func testFitUsesTheTighterAxis() {
        let wide = Viewport.fitting(CGRect(x: 0, y: 0, width: 4000, height: 200),
                                    in: window, insets: chrome)
        let tall = Viewport.fitting(CGRect(x: 0, y: 0, width: 200, height: 4000),
                                    in: window, insets: chrome)
        let visible = chrome.visibleRect(in: window)

        XCTAssertEqual(wide.zoom, visible.width / (4000 + 80), accuracy: 0.0001)
        XCTAssertEqual(tall.zoom, visible.height / (4000 + 80), accuracy: 0.0001)
    }

    /// One small box must not be blown up to fill the window.
    func testFitNeverScalesPastOneToOne() {
        let viewport = Viewport.fitting(CGRect(x: 0, y: 0, width: 40, height: 30),
                                        in: window, insets: chrome)
        XCTAssertEqual(viewport.zoom, 1)
    }

    /// A drawing far larger than the range allows still stops at the floor
    /// rather than collapsing to nothing.
    func testFitClampsToTheZoomFloor() {
        let viewport = Viewport.fitting(CGRect(x: 0, y: 0, width: 400_000, height: 400_000),
                                        in: window, insets: chrome, zoomRange: 0.1...8)
        XCTAssertEqual(viewport.zoom, 0.1)
    }

    /// Empty canvas: 1:1, with the origin somewhere a first shape is visible.
    func testEmptyCanvasSitsAtOneToOneInClearSpace() {
        let viewport = Viewport.fitting(nil, in: window, insets: chrome)
        let visible = chrome.visibleRect(in: window)

        XCTAssertEqual(viewport.zoom, 1)
        XCTAssertEqual(viewport.pan.x, visible.midX, accuracy: 0.001)
        XCTAssertEqual(viewport.pan.y, visible.midY, accuracy: 0.001)
    }

    /// A zero-area drawing — a single click, a degenerate line — is not a
    /// division by zero.
    func testDegenerateContentDoesNotDivideByZero() {
        let viewport = Viewport.fitting(CGRect(x: 100, y: 100, width: 0, height: 0),
                                        in: window, insets: chrome)
        XCTAssertEqual(viewport.zoom, 1)
        XCTAssertTrue(viewport.pan.x.isFinite && viewport.pan.y.isFinite)
    }

    /// Opening the rail must move the drawing, not leave it half-covered.
    func testOpeningTheRailReframesTheDrawing() {
        let drawing = CGRect(x: 0, y: 0, width: 1400, height: 900)
        let collapsed = ChromeInsets(top: 56, left: 78, bottom: 68, right: 24)
        let open = ChromeInsets(top: 56, left: 230, bottom: 68, right: 24)

        let a = Viewport.fitting(drawing, in: window, insets: collapsed).viewRect(drawing)
        let b = Viewport.fitting(drawing, in: window, insets: open).viewRect(drawing)

        XCTAssertGreaterThan(b.minX, a.minX)
        XCTAssertGreaterThanOrEqual(b.minX, open.visibleRect(in: window).minX)
    }

    /// A window too short for its own chrome must not produce a negative rect.
    func testTinyWindowStillProducesAUsableFit() {
        let cramped = CGRect(x: 0, y: 0, width: 200, height: 100)
        let viewport = Viewport.fitting(CGRect(x: 0, y: 0, width: 800, height: 600),
                                        in: cramped, insets: chrome)
        XCTAssertGreaterThan(viewport.zoom, 0)
        XCTAssertTrue(viewport.pan.x.isFinite && viewport.pan.y.isFinite)
    }
}
