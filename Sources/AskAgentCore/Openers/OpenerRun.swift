/// Whether an opener's command asks before it runs (ADR-0148), and how the question and its outcome are worded.
public enum OpenerRun: Sendable, Equatable {
    /// Run it: the person allowed it always, or runs everything unasked.
    case run
    /// Ask first. `remembers` is whether "always" is offered: not under `--ask all`, which asks every time.
    case ask(remembers: Bool)

    /// What to do with `rule`'s command, under the run's approvals and what was allowed always.
    public static func decide(_ rule: OpenerRule, policy: ApprovalPolicy, grants: OpenerGrants) -> OpenerRun {
        if policy.flag == .askAlways { return .ask(remembers: false) }
        if policy.flag == .yes || policy.section.defaultMode == .allow || grants.allows(rule) { return .run }
        return .ask(remembers: true)
    }

    /// The arguments as one line a person can read before allowing them, each kept apart: an argument that is not plain is in single
    /// quotes, as a shell would need it, though no shell reads it.
    public static func shown(_ arguments: [String]) -> String {
        arguments.map { argument in
            let plain =
                !argument.isEmpty
                && argument.unicodeScalars.allSatisfy { scalar in
                    scalar.isASCII
                        && (scalar.properties.isAlphabetic || scalar.properties.numericType != nil
                            || "-_./:=+,@%{}".unicodeScalars.contains(scalar))
                }
            return plain ? argument : "'" + argument.replacing("'", with: #"'\''"#) + "'"
        }
        .joined(separator: " ")
    }
}
