/// The `environment` section of a configuration file: what commands the model runs may and may not inherit of ask's own environment
/// (ADR-0106). Only names, never values.
public struct EnvironmentSection: Sendable, Equatable, CustomStringConvertible {
    /// The most names one list may hold, far above any real use, so a file cannot grow the environment check without bound.
    public static let limit = 256

    /// Names a command is given even if ask would withhold them. Exact names only.
    public var pass: [String]
    /// Names a command is not given. A name ending in `*` withholds every name that starts with what precedes it.
    public var withhold: [String]

    /// A section of these names, each list sorted and without repeats.
    public init(pass: [String] = [], withhold: [String] = []) {
        self.pass = Set(pass).sorted()
        self.withhold = Set(withhold).sorted()
    }

    public var isEmpty: Bool { pass.isEmpty && withhold.isEmpty }

    /// `self` with the names `section` adds: layers add to each other, and what a later layer withholds a pass cannot undo.
    public func layered(with section: EnvironmentSection) -> EnvironmentSection {
        EnvironmentSection(pass: pass + section.pass, withhold: withhold + section.withhold)
    }

    /// The names and nothing else: never a value.
    public var description: String {
        guard !isEmpty else { return "none" }
        return [
            pass.isEmpty ? nil : "pass " + pass.joined(separator: ", "),
            withhold.isEmpty ? nil : "withhold " + withhold.joined(separator: ", ")
        ]
        .compactMap { $0 }.joined(separator: "; ")
    }
}
