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
        var lines = ["(version 1)", "(allow default)"]
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

        switch policy.network {
            case .any: break
            case .none: lines.append("(deny network*)")
            case .localhost:
                lines += ["(deny network*)", "(allow network* (remote ip \"localhost:*\"))"]
        }
        if case .roots(let roots) = policy.write {
            let allowed = roots.map { "(subpath \(parameter("W", $0)))" } + Self.scratchWrites
            lines += ["(deny file-write*)", "(allow file-write* " + allowed.joined(separator: " ") + ")"]
        }
        if !policy.denyWrite.isEmpty {
            lines.append("(deny file-write* " + policy.denyWrite.map { clause($0, "DW") }.joined(separator: " ") + ")")
        }
        if !policy.denyRead.isEmpty {
            lines.append("(deny file-read* " + policy.denyRead.map { clause($0, "DR") }.joined(separator: " ") + ")")
        }
        let ancestors = policy.guardedAncestors
        if !ancestors.isEmpty {
            lines.append(
                "(deny file-write-unlink "
                    + ancestors.map { "(literal \(parameter("A", $0)))" }.joined(separator: " ") + ")")
        }
        text = lines.joined(separator: "\n") + "\n"
        self.parameters = parameters
    }

    /// The arguments to `sandbox-exec` that apply this profile, before the command to run.
    public var arguments: [String] {
        parameters.flatMap { ["-D", "\($0.name)=\($0.value)"] } + ["-p", text]
    }
}
