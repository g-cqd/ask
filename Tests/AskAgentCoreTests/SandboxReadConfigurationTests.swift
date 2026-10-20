import Foundation
import Testing

@testable import AskAgentCore

/// `sandbox.read` in `config.json` and `--read`: the same rules as `write`. Opt-in; every file narrows; a flag widens.
@Suite("The read allow-list is opt-in, narrows in files, widens only by flag, and survives a resume")
struct SandboxReadConfigurationTests {
    private func parse(_ text: String, project: Bool = false) throws(ConfigurationError) -> ConfigurationFile {
        try ConfigurationFile.parse(Array(text.utf8), path: "c.json", isProject: project)
    }

    @Test func `read takes workspace, anywhere or paths, and a project may set it`() throws {
        #expect(try parse("{sandbox: {read: 'workspace'}}", project: true).sandbox?.read == [.workspace])
        #expect(try parse("{sandbox: {read: ['~/notes']}}").sandbox?.read == [.paths(["~/notes"])])
        #expect(
            throws: ConfigurationError.outOfRange(
                path: "c.json", key: "sandbox.read",
                reason: "is \"home\": use \"workspace\", \"anywhere\" or a list of paths")
        ) { try parse("{sandbox: {read: 'home'}}") }
        #expect(
            throws: ConfigurationError.outOfRange(
                path: "c.json", key: "sandbox.read",
                reason: "has \"notes\": use an absolute path, or one starting with ~/")
        ) { try parse("{sandbox: {read: ['notes']}}") }
    }

    @Test func `unset is anywhere: today's deny list, nothing more`() {
        #expect(SandboxSection().readScope(workspace: "/w", home: "/h", always: ["/h/.gitconfig"]) == .anywhere)
    }

    @Test func `a restricted read is the intersection of the layers, plus what is always readable`() {
        let section = Configuration.defaults
            .applying(ConfigurationFile(sandbox: SandboxSection(read: [.paths(["/h"])])), from: .file("/u"))
            .applying(ConfigurationFile(sandbox: SandboxSection(read: [.anywhere])), from: .file("/p"))
            .sandbox.value
        #expect(section.read == [.paths(["/h"]), .anywhere])
        #expect(section.readScope(workspace: "/w", home: "/h", always: ["/g"]) == .roots(["/h", "/g"]))
    }

    @Test func `the flag replaces what the files said`() {
        let files = Configuration.defaults.applying(
            ConfigurationFile(sandbox: SandboxSection(read: [.workspace])), from: .file("/u"))
        let flagged = files.applying(model: nil, provider: nil, maxTurns: nil, compactAt: nil, read: .anywhere)
        #expect(flagged.sandbox.value.read == [.anywhere])
    }

    @Test func `the session record keeps it, and an older record without it still reads`() throws {
        let line = try SessionLog.line(forSandbox: SandboxSection(read: [.workspace]))
        #expect(String(decoding: line, as: UTF8.self) == #"{"read":["workspace"],"type":"sandbox","write":[]}"# + "\n")
        var tree = SessionTree()
        try tree.append(.user("x"))
        var old = try SessionLog.snapshot(tree)
        old += Array(#"{"network":"none","type":"sandbox","write":[]}"#.utf8) + [0x0A]
        let decoded = try SessionLog.decode(old)
        #expect(decoded.sandbox == SandboxSection(network: SandboxPolicy.Network.none))
        let resumed = Configuration.defaults.applying(
            session: SandboxSection(read: [.workspace]), flaggedNetwork: false, flaggedWrite: false, flaggedRead: false)
        #expect(resumed.sandbox.value.read == [.workspace])
    }

    @Test func `the section says it`() {
        #expect(SandboxSection(read: [.workspace]).description == "read workspace")
    }
}
