import AskAgentCore
import Foundation
import Testing

@testable import AskSession

/// `cc`, `git`, `python3` and `swift` in `/usr/bin` go through `xcrun`, which loads its library from the developer directory:
/// a run kept to its workspace for reading must be able to read that, wherever Xcode is and whatever it is called.
@Suite("A run that reads only its workspace can still read the Xcode this Mac uses")
struct DeveloperToolsReadsTests {
    @Test(arguments: [
        ["/Applications/Xcode_26.6.app/Contents/Developer", "/Applications/Xcode_26.6.app"],
        ["/Applications/Xcode-beta.app", "/Applications/Xcode-beta.app"],
        ["/Users/me/Tools/Xcode.app/Contents/Developer/", "/Users/me/Tools/Xcode.app"],
        ["/Volumes/X/Outer.app/Contents/Inner.app/Contents/Developer", "/Volumes/X/Outer.app"],
        ["/Library/Developer/CommandLineTools", ""], ["/", ""], ["", ""], ["Xcode.app/Contents/Developer", ""],
        ["/Users/me/.app/Contents/Developer", ""], ["/Users/me/Documents", ""]
    ])
    func `only an application is allowed, the outermost the directory is in`(pair: [String]) {
        #expect(ConfigurationSource.application(holding: pair[0]) ?? "" == pair[1])
    }

    @Test func `the variable names it, and so does the link xcode-select keeps, each when it is there`() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ask-developer-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let link = folder + "/xcode_select_link"
        let named = ["DEVELOPER_DIR": "/Applications/Xcode_26.6.app/Contents/Developer"]
        #expect(ConfigurationSource.developerTools(environment: [:], link: link).isEmpty, "no link, no variable")
        #expect(ConfigurationSource.developerTools(environment: named, link: link) == ["/Applications/Xcode_26.6.app"])
        try FileManager.default.createSymbolicLink(
            atPath: link,
            withDestinationPath: "/Applications/Xcode-beta.app/Contents/Developer"
        )
        #expect(ConfigurationSource.developerTools(environment: [:], link: link) == ["/Applications/Xcode-beta.app"])
        let both = ConfigurationSource.developerTools(environment: named, link: link)
        #expect(both == ["/Applications/Xcode_26.6.app", "/Applications/Xcode-beta.app"])
        let none = ConfigurationSource.developerTools(
            environment: ["DEVELOPER_DIR": "/Users/me"],
            link: folder + "/absent"
        )
        #expect(none.isEmpty, "a variable that names no application allows nothing")
    }

    @Test func `it is read by a run kept to its workspace, beside the workspace, and by no other run more than before`()
    {
        let source = ConfigurationSource(
            workingDirectory: "/work",
            flags: ConfigurationSource.Flags(),
            environment: ["HOME": "/Users/me", "DEVELOPER_DIR": "/Applications/Xcode_26.6.app/Contents/Developer"]
        )
        let kept = source.protections(SandboxSection(write: [.workspace], read: [.workspace]))
        let library = "/Applications/Xcode_26.6.app/Contents/Developer/usr/lib/libxcrun.dylib"
        #expect(kept.authorize(.read, path: library, relativeTo: "/work") == .allowed)
        #expect(
            !kept.authorize(.read, path: "/Applications/Other.app/Contents/Info.plist", relativeTo: "/work").isAllowed
        )
        #expect(!kept.authorize(.read, path: "/Users/me/Documents/letter.txt", relativeTo: "/work").isAllowed)
        #expect(!kept.authorize(.write, path: library, relativeTo: "/work").isAllowed, "reading it is all it is for")
        let open = source.protections(SandboxSection())
        #expect(open.read == .anywhere, "a run that reads anywhere is not given a list by it")
    }
}
