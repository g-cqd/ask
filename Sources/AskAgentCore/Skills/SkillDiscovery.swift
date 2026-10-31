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
    /// How much of a file is read as text to find its head: its body is not needed to list it.
    static let headBytes = 8 << 10

    /// - Parameters:
    ///   - workingDirectory: where the project is.
    ///   - home: the user's home directory.
    ///   - sources: the harnesses whose directories are searched.
    ///   - selection: which harnesses and scopes to search.
    ///   - trust: what the user has trusted. A project's skill is text from a repository, so it loads only when its file, as it is now, is in here;
    ///     the default trusts nothing, so a caller that forgets to pass it gets no project skill, not every one.
    /// - Returns: the skills that load, the project skills that wait for trust, the ones that lost a name, what was skipped, and where it looked.
    public static func discover(
        workingDirectory: String, home: String, sources: [SkillSource], selection: SkillSelection = .standard,
        trust: ProjectTrust = ProjectTrust()
    ) -> SkillCatalog {
        var catalog = SkillCatalog()
        var seenFiles = Set<String>()
        var scannedRoots = Set<String>()
        var byName: [String: Skill] = [:]
        let boundary = projectBoundary(workingDirectory: workingDirectory, home: home)
        for root in roots(workingDirectory: workingDirectory, home: home, sources: sources, selection: selection) {
            let exists = isDirectory(root.path)
            catalog.roots.append(
                SkillCatalog.Root(path: root.path, source: root.source, scope: root.scope, exists: exists))
            // A directory already searched under another name (eight harness directories can be links to one) is not searched again.
            guard exists else { continue }
            let resolved = URL(fileURLWithPath: root.path).resolvingSymlinksInPath().path
            // A project's folder linked out of the project is searched as what it leads to, if that is the user's, and not as the project's.
            if root.scope == .project, !resolved.hasPrefix(boundary + "/") {
                catalog.skipped.append("\(root.path): links outside the project, so it is not read")
                continue
            }
            guard scannedRoots.insert(resolved).inserted else { continue }
            for candidate in candidates(in: root.path) {
                let real = URL(fileURLWithPath: candidate.file).resolvingSymlinksInPath().path
                guard !seenFiles.contains(real) else { continue }
                // A link in a repository can point at any file on the machine; read outside the sandbox, trusting it would hand the model a
                // file the sandbox asks about. The same file is still found through the user's own directories, so it is not marked seen.
                if root.scope == .project, !real.hasPrefix(boundary + "/") {
                    catalog.skipped.append("\(candidate.file): links outside the project, so it is not read")
                    continue
                }
                switch read(candidate, real: real, source: root.source, scope: root.scope) {
                    case .failure(let reason):
                        seenFiles.insert(real)
                        catalog.skipped.append("\(candidate.file): \(reason)")
                    case .success(let skill):
                        // A project's skill that is not trusted does not take the file's place: the same file may be the user's own, reached by
                        // their directory next.
                        if !admits(skill, trust: trust, into: &catalog) { continue }
                        seenFiles.insert(real)
                        place(skill, in: &catalog, byName: &byName)
                }
            }
        }
        return catalog
    }

    /// Whether `skill` may be loaded. A project's skill must be trusted as its file is now; one that is not is set aside in the catalog, once.
    private static func admits(_ skill: Skill, trust: ProjectTrust, into catalog: inout SkillCatalog) -> Bool {
        guard skill.scope == .project else { return true }
        let standing = trust.standing(of: skill.realFile, digest: skill.digest)
        guard standing != .trusted else { return true }
        if !catalog.untrusted.contains(where: { $0.skill.realFile == skill.realFile }) {
            catalog.untrusted.append(SkillCatalog.Untrusted(skill: skill, standing: standing))
        }
        return false
    }

    /// Adds `skill` under its name, or, when an earlier skill has the name, to the shadowed ones unless it is the same skill.
    private static func place(_ skill: Skill, in catalog: inout SkillCatalog, byName: inout [String: Skill]) {
        let key = skill.name.lowercased()
        if let winner = byName[key] {
            if winner.digest != skill.digest { catalog.shadowed.append(skill) }
        } else {
            byName[key] = skill
            catalog.skills.append(skill)
        }
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
                // An absolute root is used as it is (ask's own skills follow its configuration directory); any other is under the home directory.
                roots += source[keyPath: paths]
                    .map {
                        Root(path: $0.hasPrefix("/") ? $0 : home + "/" + $0, source: source.id, scope: scope)
                    }
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

    /// The topmost project directory, links resolved: a project's skill must be a file inside it.
    static func projectBoundary(workingDirectory: String, home: String) -> String {
        let top = projectDirectories(from: workingDirectory, home: home).last ?? workingDirectory
        return URL(fileURLWithPath: top).resolvingSymlinksInPath().path
    }

    static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
