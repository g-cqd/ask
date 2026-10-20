import Testing

@testable import AskAI

/// A credential file that cannot be used is reported as a sentence that says what to do, with the path and never the
/// contents.
@Suite("Credential file errors say what is wrong and what to do")
struct CredentialFileErrorDescriptionTests {
    @Test func `an exposed file names the path, the mode, and the fix`() {
        let text = CredentialFileError.exposed(path: "/h/.config/ask/credentials.json", mode: 0o644).description
        #expect(text.contains("/h/.config/ask/credentials.json"))
        #expect(text.contains("644"))
        #expect(text.contains("chmod 600 /h/.config/ask/credentials.json"))
    }

    @Test func `a damaged file says it is not credentials, and how to start again`() {
        let text = CredentialFileError.damaged(path: "/p/credentials.json").description
        #expect(text.contains("/p/credentials.json"))
        #expect(text.contains("ask logout"))
    }

    @Test func `a failed system call gives the system's reason`() {
        let text = CredentialFileError.io(path: "/p/c.json", errno: 13).description
        #expect(text.contains("/p/c.json"))
        #expect(text.lowercased().contains("permission denied"))
    }

    @Test func `a lock another ask holds names the lock file and says to try again`() {
        let text = CredentialFileError.locked(path: "/p/credentials.json.write.lock").description
        #expect(text.contains("/p/credentials.json.write.lock"))
        #expect(text.contains("try again"))
    }

    @Test func `no description is the Swift enum dump`() {
        for error in [
            CredentialFileError.exposed(path: "/p", mode: 0o666), .damaged(path: "/p"), .io(path: "/p", errno: 2),
            .locked(path: "/p")
        ] {
            #expect(!"\(error)".contains("CredentialFileError"))
            #expect(!"\(error)".contains("path:"))
        }
    }
}
