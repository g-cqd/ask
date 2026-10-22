internal import AemiJSON
public import AskAI

/// What a tool call asks of its own sandbox (roadmap 0019, ADR-0020): a network level and write and read roots, any of
/// them absent. It can only narrow the run's policy; asking for more is refused with what was asked, because only the
/// user widens the sandbox.
public struct SandboxRequest: Sendable, Equatable {
    public var network: SandboxPolicy.Network?
    /// Paths as given: absolute, or relative to the working directory.
    public var write: [String]?
    public var read: [String]?

    /// A request for these, any of them absent.
    public init(network: SandboxPolicy.Network? = nil, write: [String]? = nil, read: [String]? = nil) {
        self.network = network
        self.write = write
        self.read = read
    }

    /// Whether a call's input asks, with `"reset": true`, to undo the session's narrowing.
    public static func resets(_ input: JSONObject) -> Bool {
        struct Reset: Decodable { let reset: Bool? }
        return (try? AemiJSON.JSONDecoder().decode(Reset.self, from: input.bytes))?.reset == true
    }

    /// The request in a call's input, under the key `sandbox`; nil when the call has none.
    /// - Throws: ``SandboxRequestError`` when the key is present and not a request.
    public static func `in`(_ input: JSONObject) throws(SandboxRequestError) -> SandboxRequest? {
        struct Envelope: Decodable {
            struct Wire: Decodable {
                let network: String?
                let write: [String]?
                let read: [String]?
            }
            let sandbox: Wire?
        }
        let wire: Envelope.Wire?
        do { wire = try AemiJSON.JSONDecoder().decode(Envelope.self, from: input.bytes).sandbox } catch {
            throw SandboxRequestError("write and read are lists of paths, network is none, localhost or any")
        }
        guard let wire else { return nil }
        var request = SandboxRequest(write: wire.write, read: wire.read)
        if let name = wire.network {
            guard let level = SandboxPolicy.Network(named: name) else {
                throw SandboxRequestError("network is none, localhost or any, not \"\(name)\"")
            }
            request.network = level
        }
        return request
    }

    /// What applying this request to `policy` gives.
    public enum Outcome: Sendable, Equatable {
        /// The call runs under this policy.
        case narrowed(SandboxPolicy)
        /// The call asked for these, which the run does not allow; it does not run.
        case refused([String])
        /// A path could not be resolved.
        case invalid(String)
    }

    /// `policy` narrowed by this request for one call in `workingDirectory`, or what it asked for beyond `policy`.
    public func applied(to policy: SandboxPolicy, workingDirectory: String) -> Outcome {
        var narrowed = policy
        var refusals: [String] = []
        if let network {
            if network > policy.network {
                refusals.append("network \(network) (this run allows \(policy.network))")
            } else {
                narrowed.network = network
            }
        }
        for (paths, isWrite) in [(write, true), (read, false)] {
            guard let paths else { continue }
            var roots: [String] = []
            for path in paths {
                guard let canonical = CanonicalPath.of(path, relativeTo: workingDirectory) else {
                    return .invalid("\(path) cannot be resolved to a real location")
                }
                roots.append(canonical)
            }
            let current = isWrite ? policy.write : policy.read
            let always = isWrite ? Self.scratch : SandboxPolicy.systemReadRoots + Self.scratch
            for root in roots where !Self.allows(current, always: always, root) {
                refusals.append(
                    "\(isWrite ? "writing" : "reading") under \(root) (this run allows \(Self.describe(current)))")
            }
            if isWrite { narrowed.write = .roots(roots) } else { narrowed.read = .roots(roots) }
        }
        return refusals.isEmpty ? .narrowed(narrowed) : .refused(refusals)
    }

    /// Writable in every sandboxed run, as the profile's scratch allowance is.
    static let scratch = ["/private/tmp", "/private/var/folders"]

    private static func allows(_ scope: PathScope, always: [String], _ root: String) -> Bool {
        scope.contains(root) || always.contains { SandboxRule($0, .subpath).matches(root) }
    }

    private static func describe(_ scope: PathScope) -> String {
        guard case .roots(let roots) = scope else { return "anywhere" }
        return roots.isEmpty ? "only temporary directories" : roots.joined(separator: ", ")
    }

    /// The `sandbox` argument as the model is told about it, declared by the tools that honour it.
    public static let property =
        ToolProperty.schema(
            "sandbox",
            #"{"type":"object","description":"Narrow this call's sandbox; it cannot widen it. network: none, localhost or any. write, read: paths relative to the working directory.","properties":{"network":{"type":"string","enum":["none","localhost","any"]},"write":{"type":"array","items":{"type":"string"}},"read":{"type":"array","items":{"type":"string"}}}}"#
        )
        .optional
}
