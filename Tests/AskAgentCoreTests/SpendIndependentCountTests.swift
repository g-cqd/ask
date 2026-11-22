import AemiJSON
import AskAI
import Foundation
import Testing

@testable import AskAgentCore

/// Roadmap 0239's check: what ask says a session spent agrees with an independent count of the same log. Run by
/// `Scripts/probe-spend-count.py`, which counts each log itself and names the file of its counts in `ASK_SPEND_CHECK`; skipped otherwise,
/// since it reads the person's sessions.
@Suite(
    "A session's spend agrees with an independent count of its log",
    .enabled(if: ProcessInfo.processInfo.environment["ASK_SPEND_CHECK"] != nil)
)
struct SpendIndependentCountTests {
    /// The figures in the order the probe writes them, `nil` for one never reported.
    private static func figures(_ spend: WorkSpend) -> String {
        let usage = spend.usage
        return [
            spend.requests, spend.toolCalls, usage.input, usage.output, usage.cacheRead, usage.cacheCreation,
            spend.wallMilliseconds, spend.modelMilliseconds, spend.toolMilliseconds
        ]
        .map { $0.map(String.init) ?? "nil" }
        .joined(separator: ",")
    }

    @Test func `every log's totals agree with the probe's count`() throws {
        let path = try #require(ProcessInfo.processInfo.environment["ASK_SPEND_CHECK"])
        let checks = try AemiJSON.parse(Array(try Data(contentsOf: URL(filePath: path)))).root
        let count = checks.array?.count ?? 0
        try #require(count > 0, "the probe names at least one log")
        for check in checks.array ?? [] {
            let log = try #require(check["path"].string)
            let expected = try #require(check["expect"].string)
            let recovered = try SessionLog.recover(Array(try Data(contentsOf: URL(filePath: log))))
            #expect(
                recovered.issues.isEmpty,
                "\(log) needed repairs, which the probe does not make: \(recovered.issues)"
            )
            #expect(Self.figures(WorkSpend(of: recovered.tree.activeBranch())) == expected, "\(log)")
        }
    }
}
