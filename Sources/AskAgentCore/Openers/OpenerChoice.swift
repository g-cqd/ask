internal import AemiRegex

/// What a clicked link opens with (roadmap 0216, ADR-0148).
public enum OpenerChoice: Sendable, Equatable {
    /// The system's own choice, as before openers: nothing configured matches.
    case system
    /// This app, by name or bundle identifier.
    case app(String)
    /// These arguments, the placeholders filled, from rule `rule` (its index), which asks first unless allowed.
    case command([String], rule: Int)
    /// Not opened: why.
    case refused(String)

    /// The choice for `link` under `openers`: the first rule whose every criterion holds, else the app set for its kind, else the
    /// system's.
    public static func choose(for link: ClickedLink, in openers: OpenersSection) -> OpenerChoice {
        for (index, rule) in (openers.rules ?? []).enumerated() where matches(rule, link) {
            if let app = rule.app { return .app(app) }
            if let command = rule.command { return filled(command, with: link, rule: index) }
        }
        let app: String? =
            switch link.kind {
                case .file: openers.file
                case .folder: openers.folder
                case .web: openers.web
            }
        return app.map(OpenerChoice.app) ?? .system
    }

    private static func matches(_ rule: OpenerRule, _ link: ClickedLink) -> Bool {
        if let kind = rule.kind, kind != link.kind { return false }
        if let extensions = rule.extensions {
            guard let path = link.path, let dot = path.lastIndex(of: "."), !path[dot...].contains("/") else {
                return false
            }
            let ext = path[path.index(after: dot)...].lowercased()
            guard extensions.contains(where: { $0.lowercased() == ext }) else { return false }
        }
        if let host = rule.host?.lowercased() {
            guard let linkHost = link.host?.lowercased(), linkHost == host || linkHost.hasSuffix("." + host) else {
                return false
            }
        }
        if let source = rule.pattern {
            guard let pattern = try? Pattern(source), pattern.isMatch(in: Array((link.path ?? link.url).utf8)) else {
                return false
            }
        }
        return true
    }

    /// `command` with each placeholder replaced inside its own argument; refused where an argument would start with `-` only because
    /// of what was put in it, so a link cannot become an option.
    private static func filled(_ command: [String], with link: ClickedLink, rule: Int) -> OpenerChoice {
        let values = [
            "{path}": link.path ?? link.url, "{url}": link.url,
            "{line}": String(link.line ?? 1), "{column}": String(link.column ?? 1)
        ]
        var arguments: [String] = []
        for argument in command {
            let filled = Self.fill(argument, values)
            if filled.hasPrefix("-"), !argument.hasPrefix("-") {
                return .refused("Not run: \(link.path ?? link.url) would be read as an option.")
            }
            arguments.append(filled)
        }
        return .command(arguments, rule: rule)
    }

    /// `argument` with each `{name}` in `values` replaced, left to right in one pass: what is put in is never read again.
    private static func fill(_ argument: String, _ values: [String: String]) -> String {
        var result = ""
        var rest = Substring(argument)
        while let open = rest.firstIndex(of: "{") {
            result += rest[..<open]
            if let close = rest[open...].firstIndex(of: "}"), let value = values[String(rest[open ... close])] {
                result += value
                rest = rest[rest.index(after: close)...]
            } else {
                result.append("{")
                rest = rest[rest.index(after: open)...]
            }
        }
        return result + rest
    }
}
