import Testing

@testable import AskAgentCore

/// A refused `/resume` prints the error: it reads as words, not as the enum's dump (roadmap 0131).
@Suite("A session file error reads as words")
struct SessionFileErrorDescriptionTests {
    @Test func `a missing file names the operation and the system's reason`() {
        #expect(
            String(describing: SessionFileError.io(.open, errno: 2))
                == "could not open the file: No such file or directory")
    }

    @Test func `a session held elsewhere says so`() {
        #expect("\(SessionFileError.inUse)" == "this session is open in another ask")
        #expect("\(SessionFileError.alreadyExists)" == "the file already exists")
    }

    @Test func `an unreadable archive keeps the reason`() {
        let text = "\(SessionFileError.log(.missingHeader))"
        #expect(text.hasPrefix("the session file is not readable: ") && text.contains("missingHeader"))
    }
}
