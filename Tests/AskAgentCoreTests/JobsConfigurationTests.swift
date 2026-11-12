import Testing

@testable import AskAgentCore

/// `jobs.keepFinished` (the owner, 2026-11-06; t232): how many finished jobs ask keeps for the job tool; all of them by default, and
/// `null` says so over a lower file's limit.
@Suite("jobs.keepFinished is a number of jobs, or null for all of them")
struct JobsConfigurationTests {
    private func jobs(_ json: String) throws -> JobsSection? {
        try ConfigurationFile.parse(Array(#"{"jobs": \#(json)}"#.utf8), path: "c.json").jobs
    }

    @Test func `a number, or null, read, layered, listed and shown`() throws {
        let section = try #require(try jobs(#"{"keepFinished": 50}"#))
        #expect(section.keepFinished == 50 && section.description == "keepFinished 50" && section.limit == 50)
        let all = try #require(try jobs(#"{"keepFinished": null}"#))
        #expect(
            all.keepFinished == JobsSection.noLimit && all.value(forKey: "keepFinished") == "null" && all.limit == nil
        )
        #expect(section.layered(with: all).limit == nil, "null undoes a lower file's limit")
        #expect(section.layered(with: JobsSection()).limit == 50)
        #expect(JobsSection().limit == nil, "every finished job is kept by default")
        #expect(ConfigurationFile.keys.contains("jobs"))
    }

    @Test func `0 keeps none, and what is not a whole number of 0 or more is refused`() throws {
        #expect(try jobs(#"{"keepFinished": 0}"#)?.limit == 0)
        for json in [#"{"keepFinished": -1}"#, #"{"keepFinished": "lots"}"#, #"{"other": 1}"#] {
            #expect(throws: (any Error).self, "\(json)") { try jobs(json) }
        }
    }

    @Test func `the layers carry it, and it is in the catalog, all kept by default`() throws {
        var file = ConfigurationFile()
        file.jobs = try jobs(#"{"keepFinished": 7}"#)
        let configuration = Configuration.defaults.applying(file, from: .file("c.json"))
        #expect(configuration.jobs.value.limit == 7)
        let row = try #require(SettingCatalog.all.first { $0.path == ["jobs", "keepFinished"] })
        #expect(row.defaultValue == "null")
    }
}
