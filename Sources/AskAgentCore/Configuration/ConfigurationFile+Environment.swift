// @dl:accept -- each section decodes its keys through the one shared walk; the key tables are the data
extension ConfigurationFile {
    /// The `environment` keys; unknown keys are refused.
    struct EnvironmentDecoded: Decodable {
        var section = EnvironmentSection()
        init(from decoder: any Decoder) throws {
            var pass: [String] = []
            var withhold: [String] = []
            var shell: String?
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                switch key.stringValue {
                    case "pass": pass = try container.decode([String].self, forKey: key)
                    case "withhold": withhold = try container.decode([String].self, forKey: key)
                    case "shell": shell = try container.decode(String.self, forKey: key)
                    default: throw UnknownKey(key: "environment." + key.stringValue)
                }
            }
            section = EnvironmentSection(pass: pass, withhold: withhold, shell: shell)
        }
    }

    /// Every name must be a variable name, a prefix (`NAME*`) only in `withhold`, and a project's file may withhold more and pass nothing:
    /// a repository must not hand a command a secret ask would keep from it.
    static func validateEnvironment(_ section: EnvironmentSection?, path: String, isProject: Bool)
        throws(ConfigurationError)
    {
        guard let section else { return }
        for (key, names, prefixes) in [
            ("environment.pass", section.pass, false), ("environment.withhold", section.withhold, true)
        ] {
            if names.count > EnvironmentSection.limit {
                throw .outOfRange(path: path, key: key, reason: "holds more than \(EnvironmentSection.limit) names")
            }
            for name in names where !isValid(name, allowingPrefix: prefixes) {
                throw .outOfRange(
                    path: path, key: key,
                    reason: "\"\(name)\" is not a variable name" + (prefixes ? " or a prefix such as \"AWS_*\"" : ""))
            }
        }
        if let shell = section.shell {
            if isProject {
                throw .outOfRange(
                    path: path, key: "environment.shell", reason: "only the user's file may choose the shell")
            }
            if !EnvironmentSection.shellNames.contains(shell), !shell.hasPrefix("/") || shell.utf8.count > 256 {
                throw .outOfRange(
                    path: path, key: "environment.shell",
                    reason: "\"\(shell)\" is neither a shell name (zsh, bash, fish, sh, dash, ksh) nor an absolute path"
                )
            }
        }
        if isProject, !section.pass.isEmpty {
            throw .outOfRange(
                path: path, key: "environment.pass", reason: "a project's file may withhold more, not pass any")
        }
    }

    /// Letters, digits and `_`, not starting with a digit, at most 128 bytes; with a prefix, a final `*` after at least one such character.
    private static func isValid(_ name: String, allowingPrefix: Bool) -> Bool {
        let body = allowingPrefix && name.hasSuffix("*") ? String(name.dropLast()) : name
        guard (1 ... 128).contains(body.utf8.count), let first = body.utf8.first, !(0x30 ... 0x39).contains(first)
        else { return false }
        return body.utf8.allSatisfy {
            ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) || $0 == 0x5F
        }
    }
}
