internal import Darwin
internal import Foundation

/// Which folders a controller may start a new session in (ADR-0170): `policy.gatewayStart` must not forbid it, `gateway.folders` must
/// list at least one existing directory, and the requested folder, once `~/` and every symlink are resolved, must be one of those
/// roots or inside one.
enum GatewayStartPolicy {
    /// Why starting a session was refused, with words safe to show the controller.
    struct Refusal: Error, Equatable {
        let reason: String
    }

    /// The canonical directories `allowed` names that exist now; empty when `policyAllows` is false.
    static func canonicalFolders(allowed: [String]?, policyAllows: Bool, home: String?) -> [String] {
        guard policyAllows, let allowed else { return [] }
        var seen: Set<String> = []
        var out: [String] = []
        for entry in allowed {
            guard let resolved = canonicalDirectory(expand(entry, home: home)), seen.insert(resolved).inserted else {
                continue
            }
            out.append(resolved)
        }
        return out
    }

    /// Resolves `requested` and checks it is inside `allowed` while `policyAllows` holds; returns the canonical directory path.
    static func resolve(
        _ requested: String,
        allowed: [String]?,
        policyAllows: Bool,
        home: String?
    ) throws(Refusal) -> String {
        guard policyAllows else {
            throw Refusal(
                reason: "your organisation does not allow starting sessions from the gateway (policy.gatewayStart)"
            )
        }
        let roots = canonicalFolders(allowed: allowed, policyAllows: true, home: home)
        guard !roots.isEmpty else {
            throw Refusal(reason: "this computer lists no gateway.folders to start a session in")
        }
        guard let target = canonicalDirectory(expand(requested, home: home)) else {
            throw Refusal(reason: "that folder does not exist on this computer")
        }
        let inside = roots.contains { root in
            target == root || root == "/" || target.hasPrefix(root + "/")
        }
        guard inside else {
            throw Refusal(reason: "that folder is outside this computer's gateway.folders")
        }
        return target
    }

    private static func expand(_ path: String, home: String?) -> String {
        guard let home, !home.isEmpty else { return path }
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + String(path.dropFirst(1)) }
        return path
    }

    private static func canonicalDirectory(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        var info = stat()
        guard stat(resolved, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { return nil }
        return String(cString: resolved)
    }
}
