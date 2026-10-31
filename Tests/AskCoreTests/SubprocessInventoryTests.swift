internal import Foundation
internal import Testing

/// Roadmap 0101: system APIs before subprocesses (`development/WHITE-PAPER.md`, "System APIs before subprocesses"). A process is
/// started only where the inventory says why; a new one fails here until it is added to the inventory, with its reason.
@Suite("Processes are started only where the inventory says why")
struct SubprocessInventoryTests {
    /// Each file that may start a process, and why no system API does the job.
    private static let inventory: [String: String] = [
        "Job.swift": "the model's commands: running them is the bash tool's point",
        "JobProcess.swift": "the model's commands, under sandbox-exec, which has no public API replacement",
        "BashTool.swift": "the bash tool's types for the commands it starts",
        "JobWatchdog+Process.swift": "must outlive a SIGKILL of ask, which only another process can",
        "SelfCheck.swift": "a new build of ask must be started to show it can start, before a reload",
        "ProjectLister.swift": "git is the authority on what it ignores",
        "StdioTransport.swift": "an MCP stdio server is a process by the protocol",
        "StdioTransport+Run.swift": "an MCP stdio server is a process by the protocol",
        "Reexec.swift": "/reload replaces ask with its new build: execve, not a child"
    ]

    private static let launches = [
        "import Subprocess", "Subprocess.run(", "posix_spawn(", "posix_spawnp(", "execve(", "execv(", "execvp(",
        "Process()",
        "popen(", "system("
    ]

    @Test func `no file outside the inventory starts a process`() throws {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: root.appending(path: "Package.swift").path) {
            root = root.deletingLastPathComponent()
            try #require(root.path != "/", "could not locate the repository root")
        }
        var offenders: [String] = []
        var used: Set<String> = []
        let walker = FileManager.default.enumerator(
            at: root.appending(path: "Sources"), includingPropertiesForKeys: nil)
        for case let url as URL in walker ?? FileManager.default.enumerator(atPath: "/")!
        where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
                && Self.launches.contains(where: line.contains)
            {
                if Self.inventory[url.lastPathComponent] == nil {
                    offenders.append("\(url.lastPathComponent):\(number + 1)")
                } else {
                    used.insert(url.lastPathComponent)
                }
            }
        }
        #expect(
            offenders.isEmpty,
            "A process is started outside the inventory: use a system API, or add the file with its reason: \(offenders)"
        )
        #expect(
            used == Set(Self.inventory.keys),
            "Inventory entries that start nothing any more: \(Set(Self.inventory.keys).subtracting(used))")
    }
}
