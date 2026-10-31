internal import Testing

@testable import AskAgentCore

/// A value a key does not take is refused naming the key and saying what it takes, from the catalog (roadmap 0118): the same words for a
/// string it does not know and for a value of the wrong JSON type, never the decoder's own text or another key's advice.
@Suite("A refused value names its key and what the key takes")
struct SettingTypeErrorTests {
    private func refusal(_ text: String) -> String {
        do {
            _ = try ConfigurationFile.parse(Array(text.utf8), path: "c.json")
            return "accepted"
        } catch {
            return error.description
        }
    }

    @Test(arguments: [
        (#"{"ui": {"mouse": 3}}"#, #"c.json: "ui.mouse" is 3: use true or false"#),
        (#"{"ui": {"scrollLines": "3"}}"#, #"c.json: "ui.scrollLines" is "3": use a whole number"#),
        (#"{"skills": {"maxListed": 1.5}}"#, #"c.json: "skills.maxListed" is 1.5: use a whole number"#),
        (#"{"model": 5}"#, #"c.json: "model" is 5: use a string"#),
        (
            #"{"sandbox": {"network": true}}"#,
            #"c.json: "sandbox.network" is true: use "none", "localhost", "provider" or "any""#
        ),
        (#"{"ui": {"spinner": "wobble"}}"#, #"c.json: "ui.spinner" is "wobble": use "#),
        (
            #"{"maxTurns": "lots"}"#,
            #"c.json: "maxTurns" is "lots": use a whole number of at least 1, or null for no limit"#
        ),
        (#"{"maxTurns": 2.5}"#, #"c.json: "maxTurns" is 2.5: use a whole number of at least 1, or null for no limit"#),
        (#"{"sandbox": {"hide": "~/notes"}}"#, #"c.json: "sandbox.hide" is "~/notes": use a list of paths"#),
        (#"{"compactAt": true}"#, #"c.json: "compactAt" is true: use a share of the window"#)
    ])
    func `the message names the key, the value and what it takes`(file: String, start: String) {
        let message = refusal(file)
        #expect(message.hasPrefix(start), "\(message)")
    }

    @Test func `every catalog row says what it takes, and choices list their words`() {
        for setting in SettingCatalog.all {
            #expect(!setting.expected.isEmpty, "\(setting.path)")
            if case .choice(let words) = setting.kind {
                #expect(words.allSatisfy { setting.expected.contains("\"\($0)\"") }, "\(setting.path)")
            }
        }
    }
}
