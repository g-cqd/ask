import Foundation
import Testing

@testable import AskAgentCore

@Suite("The configuration write keeps a symlinked settings file a symlink")
struct ConfigEditorSymlinkTests {
    @Test func `writing through a symlink updates the target and keeps the link`() throws {
        let directory = NSTemporaryDirectory() + "ask-symlink-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: directory + "/dotfiles", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let target = directory + "/dotfiles/settings.json"
        let link = directory + "/settings.json"
        try "{}".write(toFile: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
        try ConfigEditor.writeAtomically(Array(#"{"a":1}"#.utf8), to: link, preserving: nil)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link)) == target)
        #expect(try String(contentsOfFile: target, encoding: .utf8) == #"{"a":1}"#)
    }
}
