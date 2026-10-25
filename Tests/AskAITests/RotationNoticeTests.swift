import Testing

@testable import AskAI

/// What a person is told when the server rotated their sign-in and the file could not take the new one (roadmap 0056, ADR-0082): once
/// per failure, with the reason, and again if it happens again after a save worked.
@Suite("A sign-in that could not be saved is announced once per failure")
struct RotationNoticeTests {
    @Test func `nothing is said while nothing is unsaved`() {
        let notice = RotationNotice(provider: "Claude")
        #expect(notice.message(unsavedBecause: nil) == nil && notice.message(unsavedBecause: nil) == nil)
    }

    @Test
    func `the first call that finds it unsaved says so, naming the provider and the reason, and what happens next`()
        throws
    {
        let message = try #require(RotationNotice(provider: "Codex").message(unsavedBecause: "the file is locked"))
        #expect(message.contains("Codex") && message.contains("the file is locked"))
        #expect(message.contains("again on the next request") && message.contains("sign in again"))
    }

    @Test func `it does not repeat while the same failure goes on`() {
        let notice = RotationNotice(provider: "Claude")
        #expect(notice.message(unsavedBecause: "disk full") != nil)
        #expect(
            notice.message(unsavedBecause: "disk full") == nil && notice.message(unsavedBecause: "disk full") == nil)
    }

    @Test func `once it was saved a later failure is announced again`() {
        let notice = RotationNotice(provider: "Claude")
        #expect(notice.message(unsavedBecause: "disk full") != nil)
        #expect(notice.message(unsavedBecause: nil) == nil)
        #expect(notice.message(unsavedBecause: "locked") != nil)
    }
}
