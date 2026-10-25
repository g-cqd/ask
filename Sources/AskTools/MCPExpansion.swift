internal import AskAgentCore

/// `${NAME}` in a server's settings, filled from ask's own environment when the server is started (ADR-0099): a token can be named in the
/// configuration without being written in it.
enum MCPExpansion {
    /// A variable the settings name and the environment does not have.
    struct Missing: Error, Equatable {
        let name: String
    }

    /// `values` with every `${NAME}` replaced.
    /// - Throws: ``Missing`` for the first variable that is not set (an empty one counts as set).
    static func expand(_ values: [String: String], from environment: [String: String]) throws(Missing) -> [String:
        String]
    {
        var result: [String: String] = [:]
        for (key, value) in values { result[key] = try expand(value, from: environment) }
        return result
    }

    private static func expand(_ text: String, from environment: [String: String]) throws(Missing) -> String {
        try MCPServerSetting.expandingVariables(in: text) { (name: String) throws(Missing) -> String in
            guard let value = environment[name] else { throw Missing(name: name) }
            return value
        }
    }
}
