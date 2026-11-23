import Foundation
import Testing

@testable import AskAgentCore

/// Other apps' files in the user's temporary folder (security audit 2026-11-22, MED-07): Sunset's are kept from reading and
/// writing, by how their names start; the folder itself stays open, as the toolchain writes there whatever `TMPDIR` says.
@Suite("Other apps' temporary files are kept from commands")
struct SandboxTemporaryFilesTests {
    private let home = FileManager.default.temporaryDirectory.appending(path: "ask-tempfiles-\(UUID().uuidString)").path

    private func policy(temporary: String?) -> SandboxPolicy {
        SandboxPolicy.standard(
            home: home,
            configDirectory: home + "/.config/ask",
            stateDirectory: home + "/.local/state/ask",
            temporaryDirectory: temporary
        )
    }

    @Test func `Sunset's temporary files cannot be read or written, the rest of the folder can`() {
        let folder = home + "/T"
        let policy = policy(temporary: folder)
        for name in [
            "sunset-store-1.crx", "sunset-notification-2.png", "sunset-import-3/places.sqlite",
            "SunsetBlocking/list.json"
        ] {
            #expect(!policy.authorize(.read, path: folder + "/" + name, relativeTo: home).isAllowed, "\(name)")
            #expect(!policy.authorize(.write, path: folder + "/" + name, relativeTo: home).isAllowed, "\(name)")
        }
        for name in ["xcrun_db", "TemporaryDirectory.x/vfs.yaml", "build.log", "Sunset.txt"] {
            #expect(policy.authorize(.read, path: folder + "/" + name, relativeTo: home).isAllowed, "\(name)")
        }
        #expect(
            self.policy(temporary: nil).authorize(.read, path: folder + "/sunset-store-1.crx", relativeTo: home)
                .isAllowed
        )
    }

    @Test func `the user's own temporary folder is the system's`() {
        let named = SandboxPolicy.userTemporaryDirectory
        #expect(named?.hasPrefix("/") == true && named?.hasSuffix("/T/") == true, "\(named ?? "none")")
    }
}
