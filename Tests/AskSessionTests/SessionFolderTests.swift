import AskAgentCore
import Foundation
import Testing

@testable import AskSession

/// What a conversation reads of its folder is read of the folder it was made for, not of the one the process happens to be in
/// (ADR-0154): `ask serve` holds several sessions in one process, each with its own. These read the configuration of a folder the
/// process is not in.
@Suite("What depends on the folder is read of the folder given")
struct SessionFolderTests {
    /// A configuration directory whose user file holds `json`, and a folder to be the project.
    private func layout(_ json: String) throws -> (environment: [String: String], project: String, root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ask-folder-\(UUID().uuidString)")
        let config = root.appendingPathComponent("config/ask")
        let project = root.appendingPathComponent("work/app")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try json.write(to: config.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        let environment = [
            "XDG_CONFIG_HOME": root.appendingPathComponent("config").path, "HOME": root.path, "PATH": "/usr/bin:/bin"
        ]
        return (environment, project.resolvingSymlinksInPath().path, root)
    }

    @Test func `the modelScopes rule is the one that matches the folder given`() throws {
        let (environment, project, root) = try layout(
            #"{"modelScopes": [{"path": "~/work", "providers": ["codex"]}]}"#
        )
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(FileManager.default.currentDirectoryPath != project, "the process is elsewhere")
        let inside = ModelScopeGate.current(project: project, environment: environment)
        #expect(inside?.scope.providers == ["codex"])
        #expect(ModelScopeGate.current(project: root.path, environment: environment) == nil, "outside ~/work")
    }

    @Test
    func `whether lists leave out the models of no use is the setting of the folder given, when its file is trusted`()
        throws
    {
        let (environment, project, root) = try layout("{}")
        defer { try? FileManager.default.removeItem(at: root) }
        // The setting is in the project's own file, which counts once trusted: only the folder given can find it.
        let file = project + "/.ask/config.json"
        let bytes = Array(#"{"ui": {"onlyUsefulModels": false}}"#.utf8)
        try FileManager.default.createDirectory(atPath: project + "/.ask", withIntermediateDirectories: true)
        try Data(bytes).write(to: URL(fileURLWithPath: file))
        #expect(
            ModelFilter.onlyUseful(project: project, environment: environment),
            "not trusted yet: on, as when it is not set"
        )
        var trust = ProjectTrust()
        trust.trust(file, bytes: bytes)
        try trust.save(to: root.appendingPathComponent("config/ask/trusted.json").path)
        #expect(!ModelFilter.onlyUseful(project: project, environment: environment))
        #expect(ModelFilter.onlyUseful(project: root.path, environment: environment), "another folder has no such file")
    }
}
