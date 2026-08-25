import XCTest
import CoreGraphics
@testable import BlockpadKit

final class StyleTemplateTests: XCTestCase {

    private func subject(fg: String = "#000000", bg: String = "#FFFFFF",
                         w: Double = 120, h: Double = 48,
                         font: Double = 16, label: Bool = true,
                         control: Bool = true) -> RuleSubject {
        RuleSubject(id: UUID(), foreground: fg, background: bg,
                    size: CGSize(width: w, height: h), fontSize: font,
                    carriesLabel: label, couldBeControl: control)
    }

    /// A caption is not a button. Flagging every annotation for being under
    /// 44pt tall would make the tap-target rule worthless.
    func testTextAnnotationIsNotATapTarget() {
        let v = StyleTemplate.accessible.violations(for: subject(w: 460, h: 30, control: false))
        XCTAssertFalse(v.contains { $0.rule == .minTapTarget(44) })
    }

    /// It is still held to the text-size rule, though.
    func testTextAnnotationIsStillCheckedForSize() {
        let v = StyleTemplate.accessible.violations(for: subject(w: 460, h: 30, font: 11, control: false))
        XCTAssertTrue(v.contains { $0.rule == .minFontSize(16) })
    }

    // MARK: - Only one template checks anything

    func testOnlyAccessibleCarriesRules() {
        XCTAssertTrue(StyleTemplate.accessible.isChecked)
        for template in [StyleTemplate.modernMinimal, .storyboard, .userStory] {
            XCTAssertFalse(template.isChecked, "\(template.name) should not claim to check")
            XCTAssertTrue(template.violations(for: [subject(fg: "#EEEEEE", w: 8, h: 8, font: 4)]).isEmpty)
        }
    }

    func testACleanBlockPassesEverything() {
        XCTAssertTrue(StyleTemplate.accessible.violations(for: subject()).isEmpty)
    }

    // MARK: - Contrast

    func testLowContrastLabelFails() {
        let v = StyleTemplate.accessible.violations(for: subject(fg: "#999999", bg: "#FFFFFF"))
        XCTAssertEqual(v.count, 1)
        XCTAssertEqual(v.first?.rule, .minContrast(4.5))
        XCTAssertLessThan(v.first!.actual, 4.5)
    }

    /// The published boundary, through the whole rule rather than the maths
    /// alone: #767676 passes, #777777 does not.
    func testContrastRuleHonoursTheBoundary() {
        XCTAssertTrue(StyleTemplate.accessible
            .violations(for: subject(fg: "#767676", bg: "#FFFFFF"))
            .allSatisfy { $0.rule != .minContrast(4.5) })
        XCTAssertTrue(StyleTemplate.accessible
            .violations(for: subject(fg: "#777777", bg: "#FFFFFF"))
            .contains { $0.rule == .minContrast(4.5) })
    }

    /// An unlabelled shape has nothing to read, so it cannot fail contrast.
    func testUnlabelledShapeIsNotCheckedForContrast() {
        let v = StyleTemplate.accessible.violations(for: subject(fg: "#EEEEEE", bg: "#FFFFFF", label: false))
        XCTAssertTrue(v.isEmpty)
    }

    // MARK: - Tap target

    func testSmallTargetFails() {
        let v = StyleTemplate.accessible.violations(for: subject(w: 120, h: 40))
        XCTAssertEqual(v.first?.rule, .minTapTarget(44))
        XCTAssertEqual(v.first?.actual, 40)
    }

    func testExactlyFortyFourPasses() {
        XCTAssertTrue(StyleTemplate.accessible.violations(for: subject(w: 44, h: 44)).isEmpty)
    }

    /// The shortest side is what matters — a wide, short button still fails.
    func testTapTargetUsesTheShortestSide() {
        let v = StyleTemplate.accessible.violations(for: subject(w: 400, h: 20))
        XCTAssertEqual(v.first?.actual, 20)
    }

    /// A zero-size block is mid-draw, not a violation.
    func testZeroSizedBlockIsNotFlagged() {
        let v = StyleTemplate.accessible.violations(for: subject(w: 0, h: 0))
        XCTAssertFalse(v.contains { $0.rule == .minTapTarget(44) })
    }

    // MARK: - Font size

    func testSmallTextFails() {
        let v = StyleTemplate.accessible.violations(for: subject(font: 12))
        XCTAssertEqual(v.first?.rule, .minFontSize(16))
        XCTAssertEqual(v.first?.actual, 12)
    }

    // MARK: - Reporting

    func testABlockCanBreakSeveralRulesAtOnce() {
        let v = StyleTemplate.accessible.violations(for: subject(fg: "#CCCCCC", w: 20, h: 20, font: 9))
        XCTAssertEqual(v.count, 3)
    }

    func testMessagesReadAsInstructions() {
        let contrast = StyleTemplate.accessible.violations(for: subject(fg: "#AAAAAA")).first!
        XCTAssertTrue(contrast.message.contains("needs 4.5:1"), contrast.message)
        let target = StyleTemplate.accessible.violations(for: subject(w: 30, h: 30)).first!
        XCTAssertEqual(target.message, "Target 30pt, needs 44pt")
    }

    func testViolationsCarryTheBlockTheyBelongTo() {
        let s = subject(font: 10)
        let v = StyleTemplate.accessible.violations(for: s)
        XCTAssertEqual(v.first?.blockID, s.id)
    }

    // MARK: - Lookup

    func testTemplatesResolveByID() {
        XCTAssertEqual(StyleTemplate.named("accessible"), StyleTemplate.accessible)
        XCTAssertNil(StyleTemplate.named("nope"))
        XCTAssertNil(StyleTemplate.named(nil))
    }

    /// Every template's own defaults must pass its own rules, or the template
    /// ships a violation the moment you draw with it.
    func testEachTemplateSatisfiesItself() {
        for template in StyleTemplate.all {
            let d = template.defaults
            let s = RuleSubject(id: UUID(),
                                foreground: d.stroke,
                                background: d.fill ?? "#FBF9F2",
                                size: CGSize(width: 120, height: 48),
                                fontSize: d.fontSize,
                                carriesLabel: true,
                                couldBeControl: true)
            XCTAssertTrue(template.violations(for: s).isEmpty,
                          "\(template.name) defaults break its own rules")
        }
    }
}
