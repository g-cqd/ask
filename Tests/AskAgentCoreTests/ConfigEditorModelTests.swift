import AemiJSON
import AskAI
import Foundation
import Testing

@testable import AskAgentCore

@Suite("The configuration editor reads JSON5 and changes one typed setting at a time")
struct ConfigEditorModelTests {
    private func path(_ name: String = "config.json") -> String {
        FileManager.default.temporaryDirectory.appending(path: "ask-config-\(UUID().uuidString)/\(name)").path
    }
    private func write(_ path: String, _ text: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try text.write(toFile: path, atomically: false, encoding: .utf8)
    }

    @Test func `a missing file offers editable defaults and read-only file settings`() throws {
        let editor = try ConfigEditor(path: path(), isProject: false)
        let settings = editor.settings
        #expect(editor.warnings.isEmpty && editor.fileExists == false)
        let thinkingChoices = ["unset"] + ThinkingLevel.allCases.map(\.rawValue)
        #expect(settings.contains { $0.path == ["thinking"] && $0.choices == thinkingChoices })
        #expect(
            settings.contains {
                $0.path == ["sandbox", "network"] && $0.choices == ["unset", "none", "localhost", "any"]
            })
        #expect(
            settings.contains {
                $0.path == ["ui", "spinner"] && $0.choices.count == SpinnerPreference.allCases.count + 1
            })
        #expect(settings.contains { $0.path == ["ui", "tint"] && $0.choices == ["unset", "on", "off"] })
        #expect(settings.contains { $0.path == ["skills", "enabled"] && $0.editable })
        for readOnly in [["model"], ["maxTurns"], ["ui", "inputPrefix"], ["mcp"], ["environment", "pass"]] {
            #expect(settings.contains { $0.path == readOnly && !$0.editable && $0.choices.isEmpty })
        }
    }

    @Test func `committing a boolean updates only that nested key and preserves unrelated JSON5 settings`() throws {
        let file = path()
        let json5 = """
            // a comment the editor does not claim to preserve
            {
              model: 'claude-sonnet-5-5',
              ui: {
                tint: 'off',
                prompt: 'ask> ',
              },
              future: { keep: true },
            }
            """
        try write(file, json5 + "\n")
        var editor = try ConfigEditor(path: file, isProject: false)
        #expect(editor.warnings == ["future"])
        #expect(editor.settings.first { $0.path == ["ui", "tint"] }?.value == "off")
        try editor.commit("on", at: ["ui", "tint"])
        let saved = String(decoding: try Data(contentsOf: URL(fileURLWithPath: file)), as: UTF8.self)
        #expect(saved.contains("\"model\": \"claude-sonnet-5-5\""))
        #expect(
            saved.contains("\"tint\": true") && saved.contains("\"inputPrefix\": \"ask> \""),
            "an old name is saved as the new one")
        #expect(saved.contains("\"future\": {") && saved.contains("\"keep\": true"))
        #expect(saved.hasSuffix("}\n"), "the file's trailing newline is preserved")
        #expect(!saved.contains("// a comment"), "AemiJSON re-encodes JSON5 as strict JSON; comments are not preserved")
        editor = try ConfigEditor(path: file, isProject: false)
        #expect(editor.settings.first { $0.path == ["ui", "tint"] }?.value == "on")
        #expect(editor.setting(["ui", "tint"])?.wire == .boolean)
        #expect(editor.setting(["ui", "mouse"])?.wire == .boolean)
        #expect(editor.warnings == ["future"])
    }

    @Test func `unset removes a value and its now-empty section, without removing siblings`() throws {
        let file = path()
        try write(file, "{\n\t\"sandbox\": {\n\t\t\"network\": \"none\"\n\t}\n}\n")
        var editor = try ConfigEditor(path: file, isProject: false)
        try editor.commit("unset", at: ["sandbox", "network"])
        let saved = String(decoding: try Data(contentsOf: URL(fileURLWithPath: file)), as: UTF8.self)
        #expect(saved.contains("\t\"sandbox\": {}") || saved.contains("\"sandbox\": {}"))
        #expect(!saved.contains("network"))
        editor = try ConfigEditor(path: file, isProject: false)
        #expect(editor.settings.first { $0.path == ["sandbox", "network"] }?.value == "unset")
    }

    @Test func `invalid values are refused before any bytes reach the file`() throws {
        let file = path()
        try write(file, "{\n  \"ui\": {\n    \"tint\": \"off\"\n  }\n}\n")
        let before = String(decoding: try Data(contentsOf: URL(fileURLWithPath: file)), as: UTF8.self)
        let editor = try ConfigEditor(path: file, isProject: false)
        #expect(throws: ConfigEditor.Error.self) { try editor.commit("maybe", at: ["ui", "tint"]) }
        #expect(throws: ConfigEditor.Error.self) { try editor.commit("on", at: ["ui", "unknown"]) }
        #expect(String(decoding: try Data(contentsOf: URL(fileURLWithPath: file)), as: UTF8.self) == before)
    }

    @Test func `malformed, duplicated or oversized files are refused without writing`() throws {
        for text in ["{ nope", "{\"maxTurns\":1,\"maxTurns\":2}", String(repeating: " ", count: (1 << 20) + 1)] {
            let file = path()
            try write(file, text)
            #expect(throws: ConfigurationError.self) { _ = try ConfigEditor(path: file, isProject: false) }
        }
    }

    @Test func `a project file may not turn skills on or pass environment names`() throws {
        let file = path()
        try write(file, "{}")
        let editor = try ConfigEditor(path: file, isProject: true)
        #expect(throws: ConfigEditor.Error.self) { try editor.commit("on", at: ["skills", "enabled"]) }
        #expect(throws: ConfigEditor.Error.self) {
            try editor.commit("SECRET", at: ["environment", "pass"])
        }
        #expect(String(decoding: try Data(contentsOf: URL(fileURLWithPath: file)), as: UTF8.self) == "{}")
    }

    @Test func `saved files stay owner-only and successful saves leave no temporary file`() throws {
        let file = path("nested/config.json")
        let editor = try ConfigEditor(path: file, isProject: false)
        try editor.commit("low", at: ["thinking"])
        let attributes = try FileManager.default.attributesOfItem(atPath: file)
        #expect((attributes[.posixPermissions] as? Int).map { $0 & 0o777 } == 0o600)
        let directory = (file as NSString).deletingLastPathComponent
        let entries = try FileManager.default.contentsOfDirectory(atPath: directory)
        #expect(entries == ["config.json"])
    }
}
