internal import AskAgentCore
internal import Foundation

/// What a restricted-read run can always read from the home directory (roadmap 0042, diary 42).
extension ConfigurationSource {
    /// The toolchains, git's global configuration and the files it names (git treats an unreadable include as
    /// fatal), and ssh's config and known hosts so git over ssh still works. ssh private keys stay protected:
    /// the default protections come after these allowances.
    static func developerReads(home: String) -> [String] {
        let gitFiles = [home + "/.gitconfig", home + "/.config/git/config"]
        let named = gitFiles.flatMap { path -> [String] in
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
            return GitConfigReads.paths(in: text, directory: (path as NSString).deletingLastPathComponent, home: home)
        }
        return [
            home + "/Library/Developer/Toolchains", home + "/.swiftly", home + "/.gitconfig", home + "/.config/git",
            home + "/.ssh/config", home + "/.ssh/known_hosts"
        ] + named
    }
}
