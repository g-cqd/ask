/// A ``SandboxPolicy`` as a Seatbelt profile, and the parameters it refers to (ADR-0035).
///
/// - **Paths are data.** Each is passed as a `-D name=value` parameter and named in the profile with `(param …)`;
///   none is ever spliced into the profile's text, so no path can add a rule (probed in ADR-0020).
/// - **Protections come last.** Seatbelt applies the last rule that matches, so the denials follow every allowance
///   and a protected path inside a writable root is still protected.
/// - **Every ancestor of a protected path is guarded.** Rules match paths, so renaming a protected directory's
///   parent away, editing the copy and renaming it back would sidestep them (probed: the config ends up
///   tampered). Denying unlink of each ancestor, which is what a rename of it is, stops that.
public struct SeatbeltProfile: Sendable, Equatable {
    /// A named value the profile refers to.
    public struct Parameter: Sendable, Equatable {
        public let name: String
        public let value: String
    }

    public let text: String
    public let parameters: [Parameter]

    /// What a strict write scope still needs to write: the null device and terminals, and scratch space.
    static let scratchWrites = [
        "(literal \"/dev/null\")", "(literal \"/dev/zero\")", "(literal \"/dev/tty\")",
        "(literal \"/dev/dtracehelper\")", "(subpath \"/private/tmp\")", "(subpath \"/private/var/folders\")"
    ]

    /// Compiles `policy`.
    public init(_ policy: SandboxPolicy) {
        var lines = ["(version 1)"]
        var parameters: [Parameter] = []

        /// Names `value` as a new parameter and returns the profile's reference to it.
        func parameter(_ prefix: String, _ value: String) -> String {
            let name = "\(prefix)\(parameters.count)"
            parameters.append(Parameter(name: name, value: value))
            return "(param \"\(name)\")"
        }
        func clause(_ rule: SandboxRule, _ prefix: String) -> String {
            "(\(rule.kind == .subpath ? "subpath" : "literal") \(parameter(prefix, rule.path)))"
        }
        /// One rule, `(head clause clause …)`, or nothing when there are no clauses.
        func rule(_ head: String, _ clauses: [String]) {
            if !clauses.isEmpty { lines.append("(\(head) " + clauses.joined(separator: " ") + ")") }
        }
        /// The clauses a set of roots becomes, each a parameter named with `prefix`.
        func roots(_ paths: [String], _ prefix: String, _ kind: String = "subpath") -> [String] {
            paths.map { "(\(kind) \(parameter(prefix, $0)))" }
        }

        if case .roots(let readable) = policy.read {
            // Restricted reads: deny by default, then what any process needs, then the policy's allowances.
            lines += SeatbeltBase.lines
            rule("allow file-read*", roots(readable, "R"))
            switch policy.network {
                case .any: lines.append("(allow network*)")
                case .localhost: lines.append("(allow network* (remote ip \"localhost:*\"))")
                case .none: break
            }
            if case .roots(let writable) = policy.write {
                rule("allow file-write*", roots(writable, "W") + Self.scratchWrites)
            } else {
                lines.append("(allow file-write*)")
            }
        } else {
            lines.append("(allow default)")
            switch policy.network {
                case .any: break
                case .none: lines.append("(deny network*)")
                case .localhost: lines += ["(deny network*)", "(allow network* (remote ip \"localhost:*\"))"]
            }
            if case .roots(let writable) = policy.write {
                lines.append("(deny file-write*)")
                rule("allow file-write*", roots(writable, "W") + Self.scratchWrites)
            }
        }
        rule("deny file-write*", policy.denyWrite.map { clause($0, "DW") })
        rule("deny file-read*", policy.denyRead.map { clause($0, "DR") })
        rule("deny file-write-unlink", roots(policy.guardedAncestors, "A", "literal"))
        text = lines.joined(separator: "\n") + "\n"
        self.parameters = parameters
    }

    /// The arguments to `sandbox-exec` that apply this profile, before the command to run.
    public var arguments: [String] {
        parameters.flatMap { ["-D", "\($0.name)=\($0.value)"] } + ["-p", text]
    }
}
