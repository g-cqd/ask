import AemiJSON
import Foundation
import Testing

@testable import AskAgentCore

/// The `/config` editor keeps the file as written (roadmap 0170; the owner, 2026-10-31): a change replaces only the bytes of the value
/// it sets; a new key is written in the file's own style; a removed key takes its separator and its own comment lines with it.
@Suite("A change in /config keeps the file's comments, commas and key style")
struct ConfigEditorKeepsCommentsTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "ask-config-\(UUID().uuidString)")

    /// `text` saved, the editor opened on it, `change` made, and the file read back.
    private func saved(_ text: String, _ change: (inout ConfigEditor) throws -> Void) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "config.json").path
        try Data(text.utf8).write(to: URL(fileURLWithPath: file))
        var editor = try ConfigEditor(path: file, isProject: false)
        try change(&editor)
        return String(decoding: try Data(contentsOf: URL(fileURLWithPath: file)), as: UTF8.self)
    }

    @Test func `a changed value is the only bytes that change, comments and trailing commas kept`() throws {
        let text = """
            // my settings
            {
              model: 'claude-sonnet-5-5', // the one I use
              ui: {
                /* the colour of my input */
                tint: 'off',
                mouse: true,
              },
            }

            """
        let after = try saved(text) { try $0.commit("on", at: ["ui", "tint"]) }
        #expect(after == text.replacingOccurrences(of: "tint: 'off'", with: "tint: true"))
    }

    @Test func `a new key is written in the file's style: its quotes, indentation, separator and commas`() throws {
        let quoted = "{\n  \"ui\": {\n    \"tint\": \"off\"\n  }\n}\n"
        #expect(
            try saved(quoted) { try $0.commit("off", at: ["ui", "mouse"]) }
                == "{\n  \"ui\": {\n    \"tint\": \"off\",\n    \"mouse\": false\n  }\n}\n"
        )
        let bare = "{\n\tui: {\n\t\ttint: 'off',\n\t},\n}\n"
        #expect(
            try saved(bare) { try $0.commit("off", at: ["ui", "mouse"]) }
                == "{\n\tui: {\n\t\ttint: 'off',\n\t\tmouse: false,\n\t},\n}\n"
        )
    }

    @Test func `a new section goes at the end of the file's object, nested in its indentation`() throws {
        let text = "// mine\n{\n  \"model\": \"m\"\n}\n"
        #expect(
            try saved(text) { try $0.commit("off", at: ["ui", "mouse"]) }
                == "// mine\n{\n  \"model\": \"m\",\n  \"ui\": {\n    \"mouse\": false\n  }\n}\n"
        )
    }

    @Test func `a removed key takes its separator and the comment lines over it, and leaves its neighbours`() throws {
        let text = """
            {
              // why the network is off
              sandbox: { network: 'none' },
              // the look
              ui: {
                tint: 'off', // for now
                mouse: true,
              },
            }

            """
        let unset = try saved(text) { try $0.commit("unset", at: ["ui", "tint"]) }
        #expect(unset == text.replacingOccurrences(of: "    tint: 'off', // for now\n", with: ""))
        let last = "{\n  \"ui\": {\n    \"tint\": \"off\",\n    \"mouse\": true\n  }\n}\n"
        #expect(
            try saved(last) { try $0.commit("unset", at: ["ui", "mouse"]) }
                == "{\n  \"ui\": {\n    \"tint\": \"off\"\n  }\n}\n",
            "the last key's removal takes the comma before it"
        )
    }

    @Test func `an old setting name is renamed where it stands`() throws {
        let text = "{\n  // my prompt\n  ui: { prompt: 'ask> ', tint: 'off' },\n}\n"
        let after = try saved(text) { try $0.commit("on", at: ["ui", "tint"]) }
        #expect(after == "{\n  // my prompt\n  ui: { inputPrefix: 'ask> ', tint: true },\n}\n")
    }

    @Test func `a one-line file stays on one line, and a new file is written plain`() throws {
        #expect(
            try saved(#"{"ui":{"tint":"off"}}"#) { try $0.commit("on", at: ["ui", "tint"]) } == #"{"ui":{"tint":true}}"#
        )
        #expect(
            try saved("{}\n") { try $0.commit("off", at: ["ui", "mouse"]) }
                == "{\n  \"ui\": {\n    \"mouse\": false\n  }\n}\n"
        )
    }

    @Test func `the edit is made in place, and refused when it would not read as the settings to save`() throws {
        let source = Array("{}\n".utf8)
        let target = JSONValue.object(["ui": .object(["mouse": .bool(false)])])
        let format = ConfigEditorFormat(of: "{}\n")
        let edited = try #require(
            ConfigSourceEdit.edited(source, to: target, format: format),
            "made in place, not written anew"
        )
        #expect(String(decoding: edited, as: UTF8.self) == "{\n  \"ui\": {\n    \"mouse\": false\n  }\n}\n")
        #expect(
            ConfigSourceEdit.edited(Array("[1]".utf8), to: target, format: format) == nil,
            "not an object: written anew"
        )
    }
}
