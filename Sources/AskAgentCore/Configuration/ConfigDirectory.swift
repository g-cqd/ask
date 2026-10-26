/// Where ask keeps its configuration (roadmap 0028).
public enum ConfigDirectory {
    /// `$XDG_CONFIG_HOME/ask` when that is an absolute path, else `<home>/.config/ask`. A relative or empty `XDG_CONFIG_HOME` is
    /// ignored, as the XDG specification says: it would move with the working directory.
    /// - Parameters:
    ///   - environment: the environment ask was launched with.
    ///   - home: the user's home directory.
    /// - Returns: the directory's path, which may not exist.
    public static func path(environment: [String: String], home: String) -> String {
        let base = environment["XDG_CONFIG_HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? home + "/.config"
        return base + "/ask"
    }
}
