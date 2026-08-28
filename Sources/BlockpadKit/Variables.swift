import Foundation

/// A named value, and the machinery for binding block properties to one.
///
/// The point is the payload. `fill #E5E3DF` tells an agent what colour to use
/// once; `fill $surface #E5E3DF` tells it what the colour *means* and still
/// hands it something usable if it ignores the token table entirely. That
/// fallback is not redundancy — it is what makes the token safe to add, and it
/// is the same reason colours are hex rather than palette names.

// MARK: - Values

public enum VariableValue: Equatable, Codable, Sendable {
    case colour(String)
    case number(Double)

    /// What the tree prints for this value.
    public var literal: String {
        switch self {
        case .colour(let hex): return HexColor.normalized(hex) ?? hex
        case .number(let value):
            return value == value.rounded() ? "\(Int(value))" : String(format: "%.2f", value)
        }
    }

    public var colourHex: String? {
        if case .colour(let hex) = self { return hex }
        return nil
    }

    public var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    /// Whether two values could live in the same variable. A variable that
    /// changed type between modes would resolve to a colour in Light and a
    /// number in Dark.
    public func matchesType(of other: VariableValue) -> Bool {
        switch (self, other) {
        case (.colour, .colour), (.number, .number): return true
        default: return false
        }
    }
}

/// The block properties a variable can be bound to. Deliberately closed: these
/// are the five the inspector actually edits, and a binding to anything else
/// would have nowhere to show itself.
public enum BoundProperty: String, Codable, CaseIterable, Sendable {
    case fill, stroke, cornerRadius, strokeWidth, fontSize

    public var label: String {
        switch self {
        case .fill: return "Fill"
        case .stroke: return "Stroke"
        case .cornerRadius: return "Radius"
        case .strokeWidth: return "Weight"
        case .fontSize: return "Text"
        }
    }

    /// Which kind of value this property takes, so the inspector can only offer
    /// variables that fit.
    public var wantsColour: Bool { self == .fill || self == .stroke }
}

// MARK: - Variables

public struct Variable: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public private(set) var name: String
    /// One value per mode, keyed by mode name.
    public var values: [String: VariableValue]

    public init(id: UUID = UUID(), name: String, values: [String: VariableValue]) {
        self.id = id
        self.name = Variable.normalize(name)
        self.values = values
    }

    /// `$surface`, as it appears in the tree.
    public var token: String { "$\(name)" }

    public var isColour: Bool {
        values.values.first?.colourHex != nil
    }

    public mutating func rename(_ proposed: String) {
        let cleaned = Variable.normalize(proposed)
        guard !cleaned.isEmpty else { return }
        name = cleaned
    }

    /// Trims, drops a leading `$`, and turns whitespace into hyphens. A token
    /// with a space in it would break the tree, which is whitespace-separated.
    public static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasPrefix("$") { text.removeFirst() }
        let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: "-")
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-/"))
    }
}

// MARK: - Collections

/// A set of variables and the modes they vary across.
///
/// Modes belong to the collection rather than to individual variables, which is
/// Figma's model and the right one: a mode only means something if a whole set
/// switches together. Per-variable modes would let half a palette be dark while
/// the other half stayed light.
public struct VariableCollection: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public private(set) var modes: [String]
    public private(set) var variables: [Variable]

    public init(id: UUID = UUID(), name: String,
                modes: [String] = ["Default"], variables: [Variable] = []) {
        self.id = id
        self.name = name
        self.modes = modes.isEmpty ? ["Default"] : modes
        self.variables = variables
    }

    public var defaultMode: String { modes[0] }

    /// Looked up case-insensitively. The stored name keeps whatever case was
    /// typed — `$brandBlue` should stay readable — but `surface` and `Surface`
    /// must not be able to coexist, or the tree names two different colours
    /// with what a reader will take for one token.
    public func variable(named name: String) -> Variable? {
        let target = Variable.normalize(name).lowercased()
        return variables.first { $0.name.lowercased() == target }
    }

    public func variable(_ id: UUID) -> Variable? {
        variables.first { $0.id == id }
    }

    /// Adds a variable, refusing a name already in use. Two `$surface` entries
    /// in one collection would make the tree ambiguous.
    @discardableResult
    public mutating func add(_ variable: Variable) -> Bool {
        guard !variable.name.isEmpty, self.variable(named: variable.name) == nil else { return false }
        var filled = variable
        // Every mode gets a value, so resolution never depends on which mode is
        // showing when the variable happens to be created.
        if let seed = variable.values.values.first {
            for mode in modes where filled.values[mode] == nil { filled.values[mode] = seed }
        }
        variables.append(filled)
        return true
    }

    @discardableResult
    public mutating func rename(_ id: UUID, to proposed: String) -> Bool {
        let cleaned = Variable.normalize(proposed)
        guard !cleaned.isEmpty else { return false }
        // A rename onto an existing name is the same ambiguity as a duplicate add.
        if let clash = self.variable(named: cleaned), clash.id != id { return false }
        guard let index = variables.firstIndex(where: { $0.id == id }) else { return false }
        variables[index].rename(cleaned)
        return true
    }

    public mutating func remove(_ id: UUID) {
        variables.removeAll { $0.id == id }
    }

    public mutating func setValue(_ value: VariableValue, for id: UUID, mode: String) {
        guard let index = variables.firstIndex(where: { $0.id == id }),
              modes.contains(mode) else { return }
        variables[index].values[mode] = value
    }

    @discardableResult
    public mutating func addMode(_ name: String) -> Bool {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !modes.contains(cleaned) else { return false }
        modes.append(cleaned)
        // A new mode starts as a copy of the default rather than empty, so the
        // canvas does not blank the moment you switch to it.
        for index in variables.indices {
            variables[index].values[cleaned] = variables[index].values[defaultMode]
        }
        return true
    }

    @discardableResult
    public mutating func removeMode(_ name: String) -> Bool {
        // The last mode cannot go: a collection with no modes has nowhere to
        // keep its values.
        guard modes.count > 1, let index = modes.firstIndex(of: name) else { return false }
        modes.remove(at: index)
        for i in variables.indices { variables[i].values.removeValue(forKey: name) }
        return true
    }

    /// The value of a variable in a given mode, falling back to the default
    /// mode rather than returning nothing — a variable created before a mode
    /// existed should still resolve in it.
    public func value(_ id: UUID, mode: String) -> VariableValue? {
        guard let variable = variable(id) else { return nil }
        return variable.values[mode] ?? variable.values[defaultMode] ?? variable.values.values.first
    }
}

// MARK: - Binding

/// A block property pointing at a variable. The block stores the pointer, not a
/// resolved copy — otherwise renaming or recolouring a variable would change
/// nothing on the canvas.
public struct VariableBinding: Equatable, Codable, Sendable {
    public var property: BoundProperty
    public var variableID: UUID

    public init(property: BoundProperty, variableID: UUID) {
        self.property = property
        self.variableID = variableID
    }
}

// MARK: - Resolution

public enum VariableResolver {

    /// The variable a binding points at, wherever it lives.
    public static func variable(_ id: UUID, in collections: [VariableCollection])
        -> (collection: VariableCollection, variable: Variable)? {
        for collection in collections {
            if let variable = collection.variable(id) { return (collection, variable) }
        }
        return nil
    }

    /// The value a binding resolves to right now.
    ///
    /// Returns nil when the variable has been deleted, and the caller keeps the
    /// literal the block already had — a deleted variable must not blank
    /// everything that referenced it.
    public static func resolve(_ binding: VariableBinding,
                               in collections: [VariableCollection],
                               mode: String) -> VariableValue? {
        guard let found = variable(binding.variableID, in: collections) else { return nil }
        return found.collection.value(binding.variableID, mode: mode)
    }

    /// The token to print for a binding, or nil if it no longer resolves.
    public static func token(_ binding: VariableBinding,
                             in collections: [VariableCollection]) -> String? {
        variable(binding.variableID, in: collections)?.variable.token
    }
}

// MARK: - Payload

extension VariableCollection {

    /// The block that leads the tree, the same way a checked template does,
    /// because it changes how everything under it should be read.
    ///
    /// Every mode is emitted even though the canvas shows one, so an agent can
    /// generate both themes from a single sketch — which is the entire reason
    /// modes are worth having.
    public func treeHeader() -> [String] {
        guard !variables.isEmpty else { return [] }

        var lines: [String] = []
        lines.append(modes.count > 1
            ? "variables \(name) [\(modes.joined(separator: ", "))]"
            : "variables \(name)")

        let width = variables.map(\.token.count).max() ?? 0
        for variable in variables.sorted(by: { $0.name < $1.name }) {
            let padded = variable.token.padding(toLength: max(width, variable.token.count),
                                                withPad: " ", startingAt: 0)
            let values = modes.map { mode in
                (variable.values[mode] ?? variable.values[defaultMode])?.literal ?? "—"
            }
            lines.append("  \(padded)  \(values.joined(separator: "  "))")
        }
        return lines
    }
}

extension Array where Element == VariableCollection {
    /// Every collection's header, in order. Empty when nothing is defined, so a
    /// scene without variables emits a byte-identical tree to before.
    public func treeHeader() -> [String] {
        flatMap { $0.treeHeader() }
    }
}
