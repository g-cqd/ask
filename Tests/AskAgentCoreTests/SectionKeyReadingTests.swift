internal import Testing

@testable import AskAgentCore

/// Each key of a declared section reads back its own setting and no other (roadmap 0209, step 1): a file that sets one key, with the
/// catalog's example, shows a value for that key in `ask config` and none for any other. The fixture that sets every key
/// (`ConfigurationKeySourceTests`) tells two fields apart only where its values for them differ; two reading arms survived the
/// mutation run of 2026-11-08.
@Suite("Each key of a section reads its own setting")
struct SectionKeyReadingTests {
    /// `{"<section>": …}` setting only `path` (under the section) to `example`.
    private static func file(_ section: String, _ path: ArraySlice<String>, _ example: String) -> String {
        var json = example
        for name in path.reversed() { json = "{\"\(name)\": \(json)}" }
        return "{\"\(section)\": \(json)}"
    }

    private func check<Section: DeclaredSection>(_ type: Section.Type, in file: KeyPath<ConfigurationFile, Section?>)
        throws
    {
        let table = Section.settings
        let names = table.all.map(\.name)
        for setting in table.all {
            let text = Self.file(table.section, setting.row.path.dropFirst(), setting.row.example)
            let parsed = try ConfigurationFile.parse(Array(text.utf8), path: setting.name)
            let section = try #require(parsed[keyPath: file], "\(table.section).\(setting.name)")
            #expect(
                section.value(forKey: setting.name) != nil,
                "\(table.section).\(setting.name) reads nothing back"
            )
            let others = names.filter { $0 != setting.name && section.value(forKey: $0) != nil }
            #expect(others.isEmpty, "setting \(table.section).\(setting.name) shows a value for \(others)")
        }
    }

    /// The catalog lists a section's settings as its table declares them, in the same order: the order `ask config` shows them in.
    private func order<Section: DeclaredSection>(_ type: Section.Type) {
        let table = Section.settings
        let catalog = SettingCatalog.all.filter { $0.path.first == table.section }
        #expect(catalog == table.all.map(\.row), "\(table.section)")
    }

    @Test func `a file that sets one key shows a value for it and for no other key`() throws {
        try check(UISection.self, in: \.ui)
        try check(HooksSection.self, in: \.hooks)
        try check(AgentsSection.self, in: \.agents)
        try check(JobsSection.self, in: \.jobs)
        try check(SkillsSection.self, in: \.skills)
        try check(ThreadsSection.self, in: \.threads)
        try check(EnvironmentSection.self, in: \.environment)
        try check(SandboxSection.self, in: \.sandbox)
        try check(OpenersSection.self, in: \.openers)
    }

    @Test func `the catalog lists each section's settings in its table's order`() {
        order(UISection.self)
        order(HooksSection.self)
        order(AgentsSection.self)
        order(JobsSection.self)
        order(SkillsSection.self)
        order(ThreadsSection.self)
        order(EnvironmentSection.self)
        order(SandboxSection.self)
        order(OpenersSection.self)
        #expect(UISection.keys == UISection.settings.all.map(\.name))
    }
}
