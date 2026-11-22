import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskSession

/// What `ask config` shows for the `ui`, `skills` and `hooks` sections, pinned before `UISection`'s initializer changed (roadmap 0209):
/// every key's value in force (a file's, else the screen's default) and where it came from.
@Suite("ask config's section rows")
struct SectionRowsTests {
    private func rows(_ json: String) throws -> [String] {
        let file = try ConfigurationFile.parse(Array(json.utf8), path: "/home/config.json")
        let configuration = Configuration.defaults.applying(file, from: .file("/home/config.json"))
        let model = ResolvedModel(
            provider: .openAICompatible(
                name: "local",
                baseURL: try #require(URL(string: "https://example.test/v1")),
                apiKey: nil,
                headers: [:]
            ),
            model: "m"
        )
        let settings = RunSettings(
            configuration: configuration,
            model: model,
            sandbox: .unrestricted,
            applied: [],
            notices: [],
            workspace: "/work"
        )
        return settings.sectionRows
    }

    @Test func `the defaults, and a file's keys with their source`() throws {
        let defaults = try rows("{}")
        let file = try rows(
            #"{"ui": {"tint": false, "spinner": "snake", "appearance": "dark", "stopKeys": "esc", "historyLimit": 50}, "skills": {"maxListed": 4}}"#
        )
        #expect(defaults == Self.defaults)
        #expect(file == Self.file)
    }

    static let defaults: [String] = [
        #"ui        mouse             true  [default]"#,
        #"          copyOnSelect      true  [default]"#,
        #"          tint              true  [default]"#,
        #"          separator         true  [default]"#,
        #"          padding           true  [default]"#,
        #"          markdown          true  [default]"#,
        #"          highlight           [default]"#,
        #"          shimmer             [default]"#,
        #"          dim                 [default]"#,
        #"          sessionTint         [default]"#,
        #"          paths               [default]"#,
        #"          pathAncestors       [default]"#,
        #"          historyLimit      null  [default]"#,
        #"          hover               [default]"#,
        #"          leaveFinishedJob  true  [default]"#,
        #"          sessionColor      off  [default]"#,
        #"          notify            off  [default]"#,
        #"          listAllModels     false  [default]"#,
        #"          fold.tools        true  [default]"#,
        #"          fold.thinking     true  [default]"#,
        #"          fold.code         true  [default]"#,
        #"          fold.codeLines    20  [default]"#,
        #"          fold.outputLines  200  [default]"#,
        #"          fold.outputBytes  32768  [default]"#,
        #"          scrollLines       3  [default]"#,
        #"          inputRows         6  [default]"#,
        #"          sidebar           closed  [default]"#,
        #"          sidebarJobs         [default]"#,
        #"          sidebarLayout       [default]"#,
        #"          inputPrefix       ""  [default]"#,
        #"          appearance        auto  [default]"#,
        #"          durations         words  [default]"#,
        #"          spinner           line  [default]"#,
        #"          statusPath        folder  [default]"#,
        #"          statusPathSide    leading  [default]"#,
        #"          showTimeout       auto  [default]"#,
        #"          timeoutLabel      "timeout"  [default]"#,
        #"          stopKeys          both  [default]"#,
        #"          stopTwice         esc  [default]"#,
        #"          queuedOnStop      all  [default]"#,
        #"skills    enabled    true  [default]"#,
        #"          maxListed  32  [default]"#,
        #"          sources    every harness  [default]"#,
        #"hooks     maxContinues  3  [default]"#,
        #"          check         none  [default]"#,
        #"          checkTimeout  600 s  [default]"#,
        #"mcp       none"#
    ]
    static let file: [String] = [
        #"ui        mouse             true  [default]"#,
        #"          copyOnSelect      true  [default]"#,
        #"          tint              false  [/home/config.json]"#,
        #"          separator         true  [default]"#,
        #"          padding           true  [default]"#,
        #"          markdown          true  [default]"#,
        #"          highlight           [default]"#,
        #"          shimmer             [default]"#,
        #"          dim                 [default]"#,
        #"          sessionTint         [default]"#,
        #"          paths               [default]"#,
        #"          pathAncestors       [default]"#,
        #"          historyLimit      50  [/home/config.json]"#,
        #"          hover               [default]"#,
        #"          leaveFinishedJob  true  [default]"#,
        #"          sessionColor      off  [default]"#,
        #"          notify            off  [default]"#,
        #"          listAllModels     false  [default]"#,
        #"          fold.tools        true  [default]"#,
        #"          fold.thinking     true  [default]"#,
        #"          fold.code         true  [default]"#,
        #"          fold.codeLines    20  [default]"#,
        #"          fold.outputLines  200  [default]"#,
        #"          fold.outputBytes  32768  [default]"#,
        #"          scrollLines       3  [default]"#,
        #"          inputRows         6  [default]"#,
        #"          sidebar           closed  [default]"#,
        #"          sidebarJobs         [default]"#,
        #"          sidebarLayout       [default]"#,
        #"          inputPrefix       ""  [default]"#,
        #"          appearance        dark  [/home/config.json]"#,
        #"          durations         words  [default]"#,
        #"          spinner           snake  [/home/config.json]"#,
        #"          statusPath        folder  [default]"#,
        #"          statusPathSide    leading  [default]"#,
        #"          showTimeout       auto  [default]"#,
        #"          timeoutLabel      "timeout"  [default]"#,
        #"          stopKeys          esc  [/home/config.json]"#,
        #"          stopTwice         esc  [default]"#,
        #"          queuedOnStop      all  [default]"#,
        #"skills    enabled    true  [default]"#,
        #"          maxListed  4  [/home/config.json]"#,
        #"          sources    every harness  [default]"#,
        #"hooks     maxContinues  3  [default]"#,
        #"          check         none  [default]"#,
        #"          checkTimeout  600 s  [default]"#,
        #"mcp       none"#
    ]
}
