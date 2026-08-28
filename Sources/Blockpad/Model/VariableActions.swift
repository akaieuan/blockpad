import AppKit
import BlockpadKit

/// Creating, editing and deleting variables, and binding blocks to them.
///
/// All of it on the store rather than in the panels, so the two surfaces that
/// mutate a collection — the inspector's bind popover and the Variables sheet —
/// cannot drift into different rules about naming, modes or deletion.
extension SketchStore {

    /// The one collection.
    ///
    /// Figma's multiple collections earn their keep across a design system with
    /// separately published libraries. Here they would be a second level of
    /// hierarchy over a list that is usually five long, so there is one, made on
    /// first use and named for what it holds rather than for one of the two
    /// types in it.
    var variables: [Variable] {
        (collections.first?.variables ?? []).sorted { $0.name < $1.name }
    }

    func variable(_ id: UUID?) -> Variable? {
        guard let id else { return nil }
        return VariableResolver.variable(id, in: collections)?.variable
    }

    /// Variables that could hold this property's kind of value. Offering a
    /// colour for Radius is how a bind list becomes a list of mistakes.
    func candidates(for property: BoundProperty) -> [Variable] {
        variables.filter { $0.isColour == property.wantsColour }
    }

    func value(of id: UUID, in mode: String) -> VariableValue? {
        collections.first?.value(id, mode: mode)
    }

    private func withCollection(_ change: (inout VariableCollection) -> Void) {
        if collections.isEmpty {
            collections = [VariableCollection(name: "Tokens", modes: [mode])]
        }
        var collection = collections[0]
        change(&collection)
        collections[0] = collection
    }

    // MARK: - Variables

    /// Creates a variable, returning its id — or nil when the name is empty or
    /// already taken, which is the caller's cue to leave the field alone rather
    /// than silently doing nothing.
    @discardableResult
    func createVariable(named name: String, value: VariableValue) -> UUID? {
        let cleaned = Variable.normalize(name)
        guard !cleaned.isEmpty else { return nil }
        var created: UUID?
        withCollection { collection in
            let variable = Variable(name: cleaned, values: [mode: value])
            if collection.add(variable) { created = variable.id }
        }
        return created
    }

    @discardableResult
    func renameVariable(_ id: UUID, to name: String) -> Bool {
        var renamed = false
        withCollection { renamed = $0.rename(id, to: name) }
        return renamed
    }

    func setVariableValue(_ value: VariableValue, for id: UUID, mode: String) {
        withCollection { $0.setValue(value, for: id, mode: mode) }
    }

    /// Removes a variable, first writing the value it currently resolves to into
    /// everything bound to it.
    ///
    /// The canvas is unchanged by the deletion, which is the whole point: a
    /// token is a name for a colour, and losing the name must not lose the
    /// colour. Bindings are dropped rather than left dangling — they would
    /// render and export correctly either way, but the inspector would show a
    /// row bound to nothing.
    ///
    /// Paper is the one thing that does move: the document stores a theme by
    /// name, so there is nowhere to freeze an arbitrary colour into. It reverts
    /// to whatever theme was chosen underneath.
    func deleteVariable(_ id: UUID, canvas: CanvasView? = nil) {
        let options = renderOptions
        let frozen = blocks.map { block -> Block in
            guard block.bindings?.contains(where: { $0.variableID == id }) == true else { return block }
            var copy = BlockRenderer.resolved(block, options: options)
            let kept = block.bindings?.filter { $0.variableID != id } ?? []
            copy.bindings = kept.isEmpty ? nil : kept
            return copy
        }
        if let canvas { canvas.replaceAll(frozen, name: "Delete Variable") } else { blocks = frozen }
        if paperVariableID == id { paperVariableID = nil }
        withCollection { $0.remove(id) }
    }

    // MARK: - Modes

    @discardableResult
    func addMode(_ name: String) -> Bool {
        var added = false
        withCollection { added = $0.addMode(name) }
        return added
    }

    func removeMode(_ name: String) {
        withCollection { $0.removeMode(name) }
        if !availableModes.contains(mode) { mode = availableModes.first ?? "Default" }
    }

    // MARK: - Naming

    /// A name nobody has used yet, so creating a variable never fails on a
    /// collision the person could not see coming.
    func suggestedName(for property: BoundProperty) -> String {
        let stem = property.wantsColour ? "colour" : property.label.lowercased()
        if variables.first(where: { $0.name.lowercased() == stem }) == nil { return stem }
        var index = 2
        while variables.contains(where: { $0.name.lowercased() == "\(stem)-\(index)" }) { index += 1 }
        return "\(stem)-\(index)"
    }
}
