import XCTest
@testable import BlockpadKit

final class VariablesTests: XCTestCase {

    private func palette() -> VariableCollection {
        var c = VariableCollection(name: "Colour", modes: ["Light", "Dark"])
        c.add(Variable(name: "surface", values: ["Light": .colour("#FFFFFF"),
                                                 "Dark": .colour("#14181F")]))
        c.add(Variable(name: "ink", values: ["Light": .colour("#14181F"),
                                             "Dark": .colour("#F4F5F7")]))
        return c
    }

    // MARK: - Names

    func testNamesAreNormalised() {
        XCTAssertEqual(Variable.normalize("  surface  "), "surface")
        XCTAssertEqual(Variable.normalize("$surface"), "surface")
        XCTAssertEqual(Variable.normalize("$$surface"), "surface")
        // A space would break the tree, which is whitespace-separated.
        XCTAssertEqual(Variable.normalize("card radius"), "card-radius")
        XCTAssertEqual(Variable.normalize("radius/card"), "radius/card")
    }

    func testTokenIsTheNameWithOneDollar() {
        XCTAssertEqual(Variable(name: "$surface", values: [:]).token, "$surface")
    }

    // MARK: - Collections

    func testDuplicateNamesAreRefused() {
        var c = palette()
        XCTAssertFalse(c.add(Variable(name: "surface", values: ["Light": .colour("#000000")])))
        XCTAssertFalse(c.add(Variable(name: " $SURFACE ", values: ["Light": .colour("#000000")])),
                       "normalisation should catch a differently-spelled duplicate")
        XCTAssertEqual(c.variables.count, 2)
    }

    func testEmptyNameIsRefused() {
        var c = palette()
        XCTAssertFalse(c.add(Variable(name: "   ", values: ["Light": .colour("#000000")])))
    }

    func testRenameRefusesAClash() {
        var c = palette()
        let surface = c.variable(named: "surface")!
        XCTAssertFalse(c.rename(surface.id, to: "ink"))
        XCTAssertTrue(c.rename(surface.id, to: "bg"))
        XCTAssertEqual(c.variable(surface.id)?.token, "$bg")
    }

    /// Renaming to what it already is must not be treated as a clash with itself.
    func testRenameToItsOwnNameSucceeds() {
        var c = palette()
        let surface = c.variable(named: "surface")!
        XCTAssertTrue(c.rename(surface.id, to: "surface"))
    }

    /// A variable added with one value gets it in every mode, so resolution
    /// never depends on which mode happened to be showing.
    func testAddFillsEveryMode() {
        var c = VariableCollection(name: "Colour", modes: ["Light", "Dark"])
        c.add(Variable(name: "accent", values: ["Light": .colour("#F97316")]))
        let accent = c.variable(named: "accent")!
        XCTAssertEqual(c.value(accent.id, mode: "Dark")?.colourHex, "#F97316")
    }

    // MARK: - Modes

    func testNewModeCopiesTheDefault() {
        var c = palette()
        XCTAssertTrue(c.addMode("High contrast"))
        let ink = c.variable(named: "ink")!
        XCTAssertEqual(c.value(ink.id, mode: "High contrast")?.colourHex, "#14181F")
    }

    func testDuplicateModeIsRefused() {
        var c = palette()
        XCTAssertFalse(c.addMode("Dark"))
        XCTAssertEqual(c.modes.count, 2)
    }

    func testTheLastModeCannotBeRemoved() {
        var c = VariableCollection(name: "Colour", modes: ["Light"])
        XCTAssertFalse(c.removeMode("Light"))
        XCTAssertEqual(c.modes, ["Light"])
    }

    func testRemovingAModeDropsItsValues() {
        var c = palette()
        XCTAssertTrue(c.removeMode("Dark"))
        let ink = c.variable(named: "ink")!
        XCTAssertNil(c.variable(ink.id)?.values["Dark"])
        XCTAssertEqual(c.value(ink.id, mode: "Dark")?.colourHex, "#14181F",
                       "an unknown mode should fall back rather than resolve to nothing")
    }

    func testUnknownModeFallsBackToDefault() {
        let c = palette()
        let surface = c.variable(named: "surface")!
        XCTAssertEqual(c.value(surface.id, mode: "Sepia")?.colourHex, "#FFFFFF")
    }

    // MARK: - Resolution

    func testBindingResolvesPerMode() {
        let c = palette()
        let surface = c.variable(named: "surface")!
        let binding = VariableBinding(property: .fill, variableID: surface.id)
        XCTAssertEqual(VariableResolver.resolve(binding, in: [c], mode: "Light")?.colourHex, "#FFFFFF")
        XCTAssertEqual(VariableResolver.resolve(binding, in: [c], mode: "Dark")?.colourHex, "#14181F")
    }

    /// A deleted variable resolves to nothing, and the caller is expected to
    /// keep the literal the block already had. Blanking every block that
    /// referenced it would be the worst possible answer.
    func testDeletedVariableResolvesToNil() {
        var c = palette()
        let surface = c.variable(named: "surface")!
        let binding = VariableBinding(property: .fill, variableID: surface.id)
        c.remove(surface.id)
        XCTAssertNil(VariableResolver.resolve(binding, in: [c], mode: "Light"))
        XCTAssertNil(VariableResolver.token(binding, in: [c]))
    }

    func testResolutionSearchesEveryCollection() {
        var spacing = VariableCollection(name: "Spacing", modes: ["Default"])
        spacing.add(Variable(name: "radius/card", values: ["Default": .number(12)]))
        let radius = spacing.variable(named: "radius/card")!
        let binding = VariableBinding(property: .cornerRadius, variableID: radius.id)
        XCTAssertEqual(VariableResolver.resolve(binding, in: [palette(), spacing],
                                                mode: "Default")?.doubleValue, 12)
    }

    // MARK: - Values

    func testNumbersPrintWithoutTrailingZeroes() {
        XCTAssertEqual(VariableValue.number(12).literal, "12")
        XCTAssertEqual(VariableValue.number(1.5).literal, "1.50")
    }

    func testColoursNormaliseInTheLiteral() {
        XCTAssertEqual(VariableValue.colour("#fff").literal, "#FFFFFF")
    }

    func testTypeMatching() {
        XCTAssertTrue(VariableValue.colour("#FFF").matchesType(of: .colour("#000")))
        XCTAssertFalse(VariableValue.colour("#FFF").matchesType(of: .number(1)))
    }

    // MARK: - Payload

    func testHeaderListsEveryMode() {
        let lines = palette().treeHeader()
        XCTAssertEqual(lines.first, "variables Colour [Light, Dark]")
        XCTAssertTrue(lines.contains { $0.contains("$ink") && $0.contains("#14181F") && $0.contains("#F4F5F7") },
                      lines.joined(separator: "\n"))
    }

    /// One mode needs no mode list — the brackets would be noise.
    func testSingleModeHeaderOmitsTheModeList() {
        var c = VariableCollection(name: "Spacing", modes: ["Default"])
        c.add(Variable(name: "gap", values: ["Default": .number(8)]))
        XCTAssertEqual(c.treeHeader().first, "variables Spacing")
    }

    /// The acceptance test for not having broken the payload: no variables
    /// means not a single extra byte.
    func testNoVariablesEmitsNothing() {
        XCTAssertTrue(VariableCollection(name: "Colour").treeHeader().isEmpty)
        XCTAssertTrue([VariableCollection]().treeHeader().isEmpty)
    }

    func testHeaderIsSortedSoTheTreeIsStable() {
        var c = VariableCollection(name: "Colour", modes: ["Light"])
        c.add(Variable(name: "zebra", values: ["Light": .colour("#000000")]))
        c.add(Variable(name: "apple", values: ["Light": .colour("#FFFFFF")]))
        let lines = c.treeHeader()
        XCTAssertTrue(lines[1].contains("$apple"))
        XCTAssertTrue(lines[2].contains("$zebra"))
    }

    // MARK: - Persistence

    func testCollectionRoundTripsThroughJSON() throws {
        let original = palette()
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(VariableCollection.self, from: data), original)
    }
}
