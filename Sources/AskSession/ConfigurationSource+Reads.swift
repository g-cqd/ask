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

    /// Where the system records the developer directory `xcode-select` chose.
    static let developerDirectoryLink = "/var/db/xcode_select_link"

    /// The application holding the developer tools this Mac uses, when it is not the `/Applications/Xcode.app` every run can
    /// read: Xcode under another name (a beta, a version in its name) or in another place. `xcrun`, which `cc`, `git`,
    /// `python3` and `swift` in `/usr/bin` all go through, loads its library from there, and fails outright when it cannot.
    /// Named by `DEVELOPER_DIR`, or else by `xcode-select`'s link; only an application is allowed, whatever the variable says.
    static func developerTools(environment: [String: String], link: String = developerDirectoryLink) -> [String] {
        let selected = try? FileManager.default.destinationOfSymbolicLink(atPath: link)
        return [environment["DEVELOPER_DIR"], selected].compactMap { $0 }.compactMap(application(holding:))
    }

    /// The outermost application `path` is in or names, absolute; nil when it is in none.
    static func application(holding path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        var kept: [Substring] = []
        for component in path.split(separator: "/") {
            kept.append(component)
            if component.hasSuffix(".app"), component.count > 4 { return "/" + kept.joined(separator: "/") }
        }
        return nil
    }
}
