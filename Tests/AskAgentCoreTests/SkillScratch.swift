import Foundation

@testable import AskAgentCore

/// A throwaway home directory and project for discovery tests: real files and real symlinks, removed when the value goes away.
final class SkillScratch {
    let home: String
    let project: String

    init() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "ask-skills-\(UUID().uuidString)")
        home = base.appending(path: "home").path
        project = home + "/work/repo"
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(atPath: (home as NSString).deletingLastPathComponent) }

    /// Writes `text` at `path` under the home directory, making the directories.
    @discardableResult
    func write(_ path: String, _ text: String) throws -> String {
        let full = path.hasPrefix("/") ? path : home + "/" + path
        try FileManager.default.createDirectory(
            atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try text.write(toFile: full, atomically: true, encoding: .utf8)
        return full
    }

    /// A skill directory with a well-formed `SKILL.md`.
    @discardableResult
    func skill(_ name: String, in root: String, description: String = "Does a thing.", extra: String = "") throws
        -> String
    {
        try write(
            root + "/" + name + "/SKILL.md",
            "---\nname: \(name)\ndescription: \(description)\n\(extra)---\n# \(name)\nBody.\n")
    }

    func link(_ path: String, to target: String) throws {
        let full = home + "/" + path
        try FileManager.default.createDirectory(
            atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: full, withDestinationPath: target)
    }

    /// Discovery as the tests want it. A project's skills are trusted as they are unless `trusting` says otherwise, so a test about something else
    /// is not about trust; the tests about trust pass a store of their own to ``SkillDiscovery``.
    func discover(_ tokens: [String] = [], from directory: String? = nil, trusting: Bool = true) -> SkillCatalog {
        let selection = SkillSelection(tokens: tokens, knownSources: SkillSource.fixtureIDs)
        let first = SkillDiscovery.discover(
            workingDirectory: directory ?? project, home: home, sources: SkillSource.fixture, selection: selection)
        guard trusting, !first.untrusted.isEmpty else { return first }
        var trust = ProjectTrust()
        for item in first.untrusted { trust.trust(item.skill.realFile, digest: item.skill.digest) }
        return SkillDiscovery.discover(
            workingDirectory: directory ?? project, home: home, sources: SkillSource.fixture, selection: selection,
            trust: trust)
    }
}
