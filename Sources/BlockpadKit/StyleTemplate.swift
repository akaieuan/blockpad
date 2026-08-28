import Foundation
import CoreGraphics

/// A named set of drawing defaults, and — for the one template where it means
/// something — a set of rules the drawing is checked against.
///
/// The four templates are not four skins. Modern Minimal changes how a sketch
/// looks and nothing else. Accessible changes what it *means*: its rules are
/// requirements the receiving agent must honour, which is why it is the only one
/// that names itself in the payload. Building both through one "bundle of
/// colours" abstraction would have made the checkable one uncheckable.
public struct StyleTemplate: Equatable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let defaults: StyleDefaults
    public let rules: [Rule]

    public var isChecked: Bool { !rules.isEmpty }

    public init(id: String, name: String, summary: String,
                defaults: StyleDefaults, rules: [Rule] = []) {
        self.id = id
        self.name = name
        self.summary = summary
        self.defaults = defaults
        self.rules = rules
    }
}

/// What a template sets for newly drawn blocks. Never applied retroactively —
/// silently restyling work someone already did is not a default, it is damage.
public struct StyleDefaults: Equatable, Sendable {
    public let stroke: String
    public let fill: String?
    public let strokeWidth: Double
    public let cornerRadius: Double
    public let fontSize: Double
    /// Canvas paper, by name. nil leaves whatever is already set.
    public let paper: String?

    public init(stroke: String, fill: String?, strokeWidth: Double,
                cornerRadius: Double, fontSize: Double, paper: String? = nil) {
        self.stroke = stroke
        self.fill = fill
        self.strokeWidth = strokeWidth
        self.cornerRadius = cornerRadius
        self.fontSize = fontSize
        self.paper = paper
    }
}

/// A rule a block can break.
public enum Rule: Hashable, Sendable {
    /// WCAG contrast between a block's label and what it sits on.
    case minContrast(Double)
    /// Shortest side of anything carrying a label — the closest this app gets
    /// to knowing what a control is.
    case minTapTarget(Double)
    case minFontSize(Double)
}

/// Everything a rule needs to judge one block, without the kit knowing what a
/// Block is.
public struct RuleSubject: Equatable, Sendable {
    public let id: UUID
    /// Label colour. In Blockpad a block's stroke is also its text colour.
    public let foreground: String
    /// What the label sits on: the block's own fill, or the paper when it has
    /// none.
    public let background: String
    public let size: CGSize
    public let fontSize: Double
    public let carriesLabel: Bool
    /// Whether this could be a control. A labelled *closed shape* might be a
    /// button; a bare text annotation never is, however small. Without this
    /// distinction the tap-target rule flags every caption on the canvas.
    public let couldBeControl: Bool

    public init(id: UUID, foreground: String, background: String,
                size: CGSize, fontSize: Double, carriesLabel: Bool,
                couldBeControl: Bool) {
        self.id = id
        self.foreground = foreground
        self.background = background
        self.size = size
        self.fontSize = fontSize
        self.carriesLabel = carriesLabel
        self.couldBeControl = couldBeControl
    }
}

public struct Violation: Equatable, Sendable {
    public let blockID: UUID
    public let rule: Rule
    public let actual: Double
    public let required: Double
    /// The mode this reading came from, named only when it is the difference —
    /// see `violations(across:)`.
    public let mode: String?

    public init(blockID: UUID, rule: Rule, actual: Double, required: Double,
                mode: String? = nil) {
        self.blockID = blockID
        self.rule = rule
        self.actual = actual
        self.required = required
        self.mode = mode
    }

    public var message: String {
        let when = mode.map { " in \($0)" } ?? ""
        switch rule {
        case .minContrast:
            return "Contrast \(String(format: "%.1f", actual)):1\(when), needs "
                + "\(String(format: "%.1f", required)):1"
        case .minTapTarget:
            return "Target \(Int(actual))pt\(when), needs \(Int(required))pt"
        case .minFontSize:
            return "Text \(Int(actual))pt\(when), needs \(Int(required))pt"
        }
    }

    /// Which of two readings of the same rule is the one worth reporting. Every
    /// rule is a floor, so the smaller number is always the worse failure.
    func isWorse(than other: Violation) -> Bool { actual < other.actual }
}

extension StyleTemplate {

    /// What this block breaks. Empty for templates with no rules.
    public func violations(for subject: RuleSubject) -> [Violation] {
        rules.compactMap { rule in
            switch rule {
            case .minContrast(let required):
                // Only a label can fail a contrast check. An unlabelled box has
                // nothing to read.
                guard subject.carriesLabel,
                      let ratio = HexColor.contrastRatio(subject.foreground, subject.background),
                      ratio < required else { return nil }
                return Violation(blockID: subject.id, rule: rule,
                                 actual: ratio, required: required)

            case .minTapTarget(let required):
                // A labelled closed shape is the closest this app gets to
                // knowing something is a control. Stated plainly because it is
                // a heuristic, not a fact about the drawing — and deliberately
                // narrow, since flagging every caption for being under 44pt
                // tall would make the whole check worthless.
                guard subject.carriesLabel, subject.couldBeControl else { return nil }
                let shortest = Double(min(subject.size.width, subject.size.height))
                guard shortest > 0, shortest < required else { return nil }
                return Violation(blockID: subject.id, rule: rule,
                                 actual: shortest, required: required)

            case .minFontSize(let required):
                guard subject.carriesLabel, subject.fontSize < required else { return nil }
                return Violation(blockID: subject.id, rule: rule,
                                 actual: subject.fontSize, required: required)
            }
        }
    }

    public func violations(for subjects: [RuleSubject]) -> [Violation] {
        guard isChecked else { return [] }
        return subjects.flatMap { violations(for: $0) }
    }

    /// What the drawing breaks, checked in every mode at once.
    ///
    /// The classic shipped bug is a palette that passes in light and fails in
    /// dark, and nothing else in this app can see it: the token table holds
    /// every mode's value, so the same subject can be resolved in each mode and
    /// the worst reading reported.
    ///
    /// One violation per block per rule, never one per mode — the same button
    /// listed three times is a list nobody reads. The mode is named only when it
    /// is the difference: a block that fails everywhere fails for reasons that
    /// have nothing to do with modes, and "in Dark" would imply Light was fine.
    public func violations(across modes: [(mode: String, subjects: [RuleSubject])]) -> [Violation] {
        guard isChecked, !modes.isEmpty else { return [] }
        guard modes.count > 1 else { return violations(for: modes[0].subjects) }

        struct Key: Hashable { let block: UUID; let rule: Rule }
        var worst: [Key: Violation] = [:]
        var failures: [Key: Int] = [:]

        for (mode, subjects) in modes {
            for subject in subjects {
                for violation in violations(for: subject) {
                    let key = Key(block: subject.id, rule: violation.rule)
                    failures[key, default: 0] += 1
                    let candidate = Violation(blockID: violation.blockID,
                                              rule: violation.rule,
                                              actual: violation.actual,
                                              required: violation.required,
                                              mode: mode)
                    if let held = worst[key], !candidate.isWorse(than: held) { continue }
                    worst[key] = candidate
                }
            }
        }

        return worst.map { key, violation -> Violation in
            guard failures[key] == modes.count else { return violation }
            return Violation(blockID: violation.blockID, rule: violation.rule,
                             actual: violation.actual, required: violation.required)
        }
        // Dictionaries have no order and a warning list that reshuffles itself
        // between redraws is unusable.
        .sorted { $0.blockID.uuidString == $1.blockID.uuidString
            ? $0.message < $1.message
            : $0.blockID.uuidString < $1.blockID.uuidString }
    }
}

// MARK: - The templates

extension StyleTemplate {

    public static let all: [StyleTemplate] = [modernMinimal, accessible, storyboard, userStory]

    public static func named(_ id: String?) -> StyleTemplate? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// Defaults only. Nothing here is checkable, and pretending otherwise would
    /// be theatre.
    public static let modernMinimal = StyleTemplate(
        id: "modern-minimal",
        name: "Modern Minimal",
        summary: "Thin ink, generous radius, quiet fills",
        defaults: StyleDefaults(stroke: "#1F2933", fill: "#F4F5F7",
                                strokeWidth: 1.25, cornerRadius: 12,
                                fontSize: 15, paper: "Paper"))

    /// The one that earns its keep. Its rules are requirements, not suggestions,
    /// which is why it is the only template that names itself in the tree.
    public static let accessible = StyleTemplate(
        id: "accessible",
        name: "Accessible",
        summary: "WCAG AA contrast, 44pt targets, 16pt text",
        defaults: StyleDefaults(stroke: "#14181F", fill: "#FFFFFF",
                                strokeWidth: 2, cornerRadius: 8,
                                fontSize: 16, paper: "Paper"),
        rules: [.minContrast(4.5), .minTapTarget(44), .minFontSize(16)])

    public static let storyboard = StyleTemplate(
        id: "storyboard",
        name: "Storyboard",
        summary: "Captioned frames, read left to right",
        defaults: StyleDefaults(stroke: "#2B2A28", fill: nil,
                                strokeWidth: 2, cornerRadius: 6,
                                fontSize: 14, paper: "Paper"))

    public static let userStory = StyleTemplate(
        id: "user-story",
        name: "User Story",
        summary: "Actor, goal, numbered steps",
        defaults: StyleDefaults(stroke: "#2B2A28", fill: "#F6F1E7",
                                strokeWidth: 2, cornerRadius: 10,
                                fontSize: 15, paper: "Paper"))
}
