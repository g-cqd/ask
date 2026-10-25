import Testing

@testable import AskAgentCore

@Suite("A selection of skills only ever narrows")
struct SkillSelectionTests {
    @Test func `nothing named is everyone's user and project skills, and nothing bundled`() {
        let selection = SkillSelection(tokens: [], knownSources: SkillSource.fixtureIDs)
        #expect(selection.sources == nil && selection.scopes == [.user, .project] && selection.unknown.isEmpty)
        #expect(selection == .standard)
    }

    @Test func `harness names narrow the sources, in any case, with spaces and repeats`() {
        #expect(
            SkillSelection(tokens: [" Claude ", "CODEX", "claude"], knownSources: SkillSource.fixtureIDs).sources == [
                "claude", "codex"
            ])
    }

    @Test func `user and project narrow the scopes`() {
        #expect(SkillSelection(tokens: ["project"], knownSources: SkillSource.fixtureIDs).scopes == [.project])
        #expect(
            SkillSelection(tokens: ["user", "project"], knownSources: SkillSource.fixtureIDs).scopes == [
                .user, .project
            ])
    }

    @Test func `bundled alone is only the bundled, and with a harness or a scope it is added to what that gives`() {
        #expect(SkillSelection(tokens: ["bundled"], knownSources: SkillSource.fixtureIDs).scopes == [.bundled])
        #expect(
            SkillSelection(tokens: ["agy", "bundled"], knownSources: SkillSource.fixtureIDs).scopes == [
                .user, .project, .bundled
            ])
        #expect(
            SkillSelection(tokens: ["user", "bundled"], knownSources: SkillSource.fixtureIDs).scopes == [
                .user, .bundled
            ])
    }

    @Test func `a word that is neither is remembered and changes nothing`() {
        let selection = SkillSelection(tokens: ["claude", "nonsense", "", "/etc"], knownSources: SkillSource.fixtureIDs)
        #expect(selection.sources == ["claude"] && selection.unknown == ["nonsense", "/etc"])
    }

    @Test func `a path is never a harness`() {
        let selection = SkillSelection(tokens: ["/Users/x/skills", "../up"], knownSources: SkillSource.fixtureIDs)
        #expect(selection.sources == nil && selection.unknown.count == 2)
    }
}
