import Foundation
import Testing

@testable import AskAgentCore

/// The write scope and the network in `config.json`: files narrow, only flags widen, and the result is what the
/// policy enforces.
@Suite("Write scope and network: every file narrows, only the user's flags widen")
struct SandboxStrictConfigurationTests {
    private func parse(_ text: String, project: Bool = false) throws(ConfigurationError) -> ConfigurationFile {
        try ConfigurationFile.parse(Array(text.utf8), path: "c.json", isProject: project)
    }

    private func layered(_ sections: SandboxSection...) -> SandboxSection {
        sections.enumerated()
            .reduce(Configuration.defaults) { configuration, item in
                configuration.applying(ConfigurationFile(sandbox: item.element), from: .file("/\(item.offset)"))
            }
            .sandbox.value
    }

    @Test func `write takes workspace, anywhere or a list of paths, and network one of three levels`() throws {
        #expect(try parse("{sandbox: {write: 'workspace'}}").sandbox?.write == [.workspace])
        #expect(try parse("{sandbox: {write: 'anywhere'}}").sandbox?.write == [.anywhere])
        #expect(try parse("{sandbox: {write: ['~/out', '/tmp/x']}}").sandbox?.write == [.paths(["~/out", "/tmp/x"])])
        #expect(try parse("{sandbox: {network: 'localhost'}}").sandbox?.network == .localhost)
        #expect(
            try parse("{sandbox: {network: 'none', write: 'workspace'}}", project: true).sandbox?.network
                == SandboxPolicy.Network.none)
    }

    @Test func `a value that is not one of them is refused, naming the key and the choices`() {
        #expect(
            throws: ConfigurationError.outOfRange(
                path: "c.json", key: "sandbox.network", reason: "is \"local\": use \"none\", \"localhost\" or \"any\"")
        ) { try parse("{sandbox: {network: 'local'}}") }
        #expect(
            throws: ConfigurationError.outOfRange(
                path: "c.json", key: "sandbox.write",
                reason: "is \"project\": use \"workspace\", \"anywhere\" or a list of paths")
        ) { try parse("{sandbox: {write: 'project'}}") }
        #expect(
            throws: ConfigurationError.outOfRange(
                path: "c.json", key: "sandbox.write",
                reason: "has \"out\": use an absolute path, or one starting with ~/")
        ) { try parse("{sandbox: {write: ['out']}}") }
        #expect(throws: ConfigurationError.self) { try parse("{sandbox: {network: 3}}") }
    }

    @Test func `a later file cannot widen the network, only narrow it`() {
        #expect(layered(SandboxSection(network: .localhost), SandboxSection(network: .any)).network == .localhost)
        #expect(
            layered(SandboxSection(network: .any), SandboxSection(network: SandboxPolicy.Network.none)).network
                == SandboxPolicy.Network.none)
        #expect(layered(SandboxSection(network: .localhost), SandboxSection()).network == .localhost)
        #expect(layered().network == nil, "unset means ask's default, which is any")
    }

    @Test func `write scopes accumulate, so a later file narrows and never widens`() {
        let section = layered(SandboxSection(write: [.workspace]), SandboxSection(write: [.anywhere]))
        #expect(section.write == [.workspace, .anywhere])
        #expect(section.writeScope(workspace: "/w", home: "/h") == .roots(["/w"]))
    }

    @Test func `the scopes resolve to their intersection, with the home shorthand and the workspace`() {
        // The kernel's spelling (/private/var/…), which Foundation's resolvingSymlinksInPath would strip.
        let workspace = CanonicalPath.of(FileManager.default.temporaryDirectory.path, relativeTo: "/") ?? ""
        let inside = workspace + "/inside"
        #expect(SandboxSection().writeScope(workspace: workspace, home: "/h") == .anywhere)
        #expect(SandboxSection(write: [.workspace]).writeScope(workspace: workspace, home: "/h") == .roots([workspace]))
        #expect(
            SandboxSection(write: [.workspace, .paths([inside, "/elsewhere"])])
                .writeScope(workspace: workspace, home: "/h")
                == .roots([inside]), "an unrelated root drops out; one inside the workspace stays")
        #expect(
            SandboxSection(write: [.paths(["~/out"])]).writeScope(workspace: workspace, home: "/h")
                == .roots(["/h/out"]))
    }

    @Test func `flags replace the file layers, which is how only the user widens`() {
        let files = layered(SandboxSection(write: [.workspace], network: SandboxPolicy.Network.none))
        let configuration = Configuration.defaults.applying(
            ConfigurationFile(sandbox: files), from: .file("/u"))
        let flagged = configuration.applying(
            model: nil, provider: nil, maxTurns: nil, compactAt: nil, network: .any, write: .anywhere)
        #expect(flagged.sandbox.value.network == .any && flagged.sandbox.value.write == [.anywhere])
        #expect(flagged.sandbox.source == .flag("network/write"))
        let untouched = configuration.applying(model: nil, provider: nil, maxTurns: nil, compactAt: nil)
        #expect(untouched.sandbox == configuration.sandbox)
    }

    @Test func `the section says what it sets, so config and a reload show it`() {
        #expect(
            SandboxSection(write: [.workspace], network: .localhost).description == "write workspace, network localhost"
        )
        #expect(SandboxSection(write: [.paths(["/a", "/b"])]).description == "write [/a, /b]")
    }
}
