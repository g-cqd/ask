internal import AskAgentCore
internal import Darwin
internal import Foundation
internal import Testing

@testable import AskSession

/// `policy.managedSkillsOnly` (roadmap 0130): skills come from the organisation's folder alone, and only while it belongs to its owner
/// and nobody else may write it; without the policy, the organisation's folder is one source among the others.
@Suite("Only the organisation's skills", .serialized)
struct ManagedSkillsPolicyTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "ask-org-skills-\(UUID().uuidString)")
        .path

    private func skill(_ name: String, in folder: String) throws {
        try FileManager.default.createDirectory(atPath: folder + "/" + name, withIntermediateDirectories: true)
        try Data("---\nname: \(name)\ndescription: Does \(name).\n---\n# \(name)\n".utf8)
            .write(to: URL(filePath: folder + "/" + name + "/SKILL.md"))
    }

    private func names(_ origins: SkillOrigins) -> [String] {
        SkillBook(SkillsSection(), workingDirectory: root + "/project", origins: origins).catalog.skills.map { $0.name }
            .sorted()
    }

    @Test
    func `under the policy only a trusted organisation folder's skills are offered, and an untrusted one offers none`()
        throws
    {
        defer { try? FileManager.default.removeItem(atPath: root) }
        let folder = root + "/managed/skills"
        try FileManager.default.createDirectory(atPath: root + "/project", withIntermediateDirectories: true)
        try skill("org-review", in: folder)
        var policy = Configuration.defaults.policy.value
        policy.managedSkillsOnly = true
        let trusted = SkillOrigins.of(policy, folder: folder, owner: getuid())
        #expect(trusted.refusal == nil && names(trusted) == ["org-review"], "the person's own skills are not offered")
        let book = SkillBook(SkillsSection(sources: ["claude"]), workingDirectory: root + "/project", origins: trusted)
        #expect(book.catalog.skills.map { $0.name } == ["org-review"], "the person's skills.sources cannot widen it")
        #expect(chmod(folder, 0o775) == 0)
        let shared = SkillOrigins.of(policy, folder: folder, owner: getuid())
        #expect(
            names(shared).isEmpty && shared.refusal?.contains("may be written by others") == true,
            "\(shared.refusal ?? "")"
        )
        #expect(chmod(folder, 0o755) == 0)
        let someoneElse = SkillOrigins.of(policy, folder: folder, owner: getuid() + 1)
        #expect(names(someoneElse).isEmpty && someoneElse.refusal != nil)
        let missing = SkillOrigins.of(policy, folder: root + "/nowhere", owner: getuid())
        #expect(names(missing).isEmpty && missing.refusal != nil)
    }

    @Test func `without the policy the organisation's folder is one more source`() throws {
        defer { try? FileManager.default.removeItem(atPath: root) }
        let folder = root + "/managed/skills"
        try FileManager.default.createDirectory(atPath: root + "/project", withIntermediateDirectories: true)
        try skill("org-review", in: folder)
        let origins = SkillOrigins.of(Configuration.defaults.policy.value, folder: folder, owner: getuid())
        #expect(origins.imposed == nil && origins.refusal == nil)
        #expect(origins.sources.map { $0.id }.contains(SkillOrigins.organisationID) && origins.sources.count > 1)
        #expect(names(origins).contains("org-review"))
    }
}
