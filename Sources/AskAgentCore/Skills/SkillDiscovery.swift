internal import Foundation

/// Finds skills in every harness's directories and reads them without being strict about how they are written.
///
/// A skill is a directory with a `SKILL.md` (any case); a bare `name.md` with a `description` in its head, directly in a skill directory, is one
/// too. The same skill reached by two paths is one skill, because the paths are compared with every symlink resolved: on the owner's machine eight
/// harness directories are links to one. Two different skills with one name are not both offered; the first by precedence wins and the other is reported.
public enum SkillDiscovery {
    /// The deepest a skill may sit under a skill directory (`.system/skill-creator` is two).
    public static let maximumDepth = 4
    /// The most directories looked at under one skill directory, so a skills directory that is really a whole tree is not walked in full.
    public static let maximumDirectories = 600
    /// The most bytes of a skill file read.
    public static let maximumBytes = 256 << 10

    /// - Parameters:
    ///   - workingDirectory: where the project is.
    ///   - home: the user's home directory.
    ///   - sources: the harnesses whose directories are searched.
    ///   - selection: which harnesses and scopes to search.
    /// - Returns: the skills that load, the ones that lost a name, what was skipped, and where it looked.
    public static func discover(
        workingDirectory: String, home: String, sources: [SkillSource], selection: SkillSelection = .standard
    ) -> SkillCatalog {
        var catalog = SkillCatalog()
        var seenFiles = Set<String>()
        var byName: [String: Skill] = [:]
        for root in roots(workingDirectory: workingDirectory, home: home, sources: sources, selection: selection) {
            let exists = isDirectory(root.path)
            catalog.roots.append(
                SkillCatalog.Root(path: root.path, source: root.source, scope: root.scope, exists: exists))
            guard exists else { continue }
            for candidate in candidates(in: root.path) {
                let real = URL(fileURLWithPath: candidate.file).resolvingSymlinksInPath().path
                guard seenFiles.insert(real).inserted else { continue }
                switch read(candidate, real: real, source: root.source, scope: root.scope) {
                    case .failure(let reason): catalog.skipped.append("\(candidate.file): \(reason)")
                    case .success(let skill):
                        let key = skill.name.lowercased()
                        if let winner = byName[key] {
                            if winner.digest != skill.digest { catalog.shadowed.append(skill) }
                        } else {
                            byName[key] = skill
                            catalog.skills.append(skill)
                        }
                }
            }
        }
        return catalog
    }

    struct Root {
        let path: String
        let source: String
        let scope: SkillScope
    }

    /// The directories to search, in the order of precedence: each project directory from the working directory up, then the user's, then bundled.
    static func roots(workingDirectory: String, home: String, sources: [SkillSource], selection: SkillSelection)
        -> [Root]
    {
        var roots: [Root] = []
        if selection.scopes.contains(.project) {
            for directory in projectDirectories(from: workingDirectory, home: home) {
                for source in sources where selection.includes(source: source.id, scope: .project) {
                    roots += source.projectRoots.map {
                        Root(path: directory + "/" + $0, source: source.id, scope: .project)
                    }
                }
            }
        }
        for (scope, paths) in [(SkillScope.user, \SkillSource.userRoots), (.bundled, \SkillSource.bundledRoots)] {
            for source in sources where selection.includes(source: source.id, scope: scope) {
                roots += source[keyPath: paths].map { Root(path: home + "/" + $0, source: source.id, scope: scope) }
            }
        }
        return roots
    }

    /// The working directory and each ancestor up to the repository root. Under the home directory with no repository, up to just below home;
    /// outside it, only the working directory, so a checkout under `/tmp` does not read `/.agents`.
    static func projectDirectories(from workingDirectory: String, home: String) -> [String] {
        let start = URL(fileURLWithPath: workingDirectory).standardizedFileURL.path
        let top = URL(fileURLWithPath: home).standardizedFileURL.path
        guard start.hasPrefix(top + "/") else { return start == top ? [] : [start] }
        var found: [String] = []
        var current = start
        while current != top, !current.isEmpty, current != "/" {
            found.append(current)
            if FileManager.default.fileExists(atPath: current + "/.git") { break }
            current = (current as NSString).deletingLastPathComponent
        }
        return found
    }

    static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
