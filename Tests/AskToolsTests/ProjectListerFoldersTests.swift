import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// The `@` picker's listing resolves each folder once (PERF-04) and decides every path as resolving it whole did: the earlier
/// algorithm, kept here as the oracle, and the listing agree on a tree of links to files, to folders, into a protected place, through
/// a linked folder, and dangling.
@Suite("The picker's listing resolves folders once and decides as before")
struct ProjectListerFoldersTests {
    /// The listing as it was before folders were cached: every path stat'ed and resolved whole.
    private static func oracle(_ candidates: [String], in directory: String, policy: SandboxPolicy) -> ProjectListing {
        var listing = ProjectListing()
        var seen = Set<String>()
        for path in candidates.sorted() where seen.insert(path).inserted {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory + "/" + path, isDirectory: &isDirectory),
                !isDirectory.boolValue
            else { continue }
            guard policy.isUnrestricted || policy.authorize(.read, path: path, relativeTo: directory).isAllowed else {
                listing.hidden += 1
                continue
            }
            listing.paths.append(path)
        }
        return listing
    }

    @Test func `the listing agrees with resolving each path whole`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-lister-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        let home = root + "/home"
        let project = home + "/project"
        let files = FileManager.default
        for folder in [project + "/src/deep", home + "/.aws", home + "/elsewhere"] {
            try files.createDirectory(atPath: folder, withIntermediateDirectories: true)
        }
        for file in [
            project + "/a.txt", project + "/src/b.swift", project + "/src/deep/c.swift", home + "/.aws/credentials",
            home + "/elsewhere/d.txt"
        ] {
            try Data("x".utf8).write(to: URL(filePath: file))
        }
        try files.createSymbolicLink(atPath: project + "/to-file", withDestinationPath: "a.txt")
        try files.createSymbolicLink(atPath: project + "/to-secret", withDestinationPath: home + "/.aws/credentials")
        try files.createSymbolicLink(atPath: project + "/to-folder", withDestinationPath: "src")
        try files.createSymbolicLink(atPath: project + "/aws", withDestinationPath: home + "/.aws")
        try files.createSymbolicLink(atPath: project + "/dangling", withDestinationPath: "nothing.txt")
        let candidates = [
            "a.txt", "src/b.swift", "src/deep/c.swift", "to-file", "to-secret", "to-folder", "to-folder/b.swift",
            "aws/credentials",
            "dangling", "gone.txt", "src", "../elsewhere/d.txt", "src/../a.txt", "a.txt"
        ]
        for policy in [
            SandboxPolicy.standard(
                home: home,
                configDirectory: home + "/.config/ask",
                stateDirectory: home + "/.local/state/ask"
            ),
            SandboxPolicy.standard(
                home: home,
                configDirectory: home + "/.config/ask",
                stateDirectory: home + "/.local/state/ask",
                denyRead: [project + "/src/deep"]
            )
        ] {
            let listed = ProjectLister.readable(candidates, in: project, policy: policy, limit: 100)
            let expected = Self.oracle(candidates, in: project, policy: policy)
            #expect(listed.paths == expected.paths && listed.hidden == expected.hidden, "\(listed) against \(expected)")
            #expect(!listed.paths.contains("to-secret") && !listed.paths.contains("aws/credentials"), "\(listed.paths)")
            #expect(listed.paths.contains("to-folder/b.swift") && listed.paths.contains("src/b.swift"))
        }
    }
}
