internal import AskTUI
internal import AskTools
internal import Testing

@testable import AskSession

/// A job's end, once the table tells of it, goes to the conversation it was started for (owner, 2026-11-27): main's as its next
/// message, which starts a turn when none runs; a thread's to the thread; a thread that is gone's to main.
@Suite("A job's end reaches the conversation it was started for")
struct JobEndingDeliveryTests {
    @Test func `main's job's end is main's next message, and a gone thread's falls to main`() async throws {
        let fixture = try await ConversationFixture()
        fixture.conversation.deliver(
            JobEnding(job: "job-1", owner: nil, report: "[job-1 ended]"),
            update: fixture.update
        )
        fixture.conversation.deliver(
            JobEnding(job: "job-2", owner: "thread-9", report: "[job-2 ended]"),
            update: fixture.update
        )
        #expect(fixture.updates.contains(.submitPrompt("[job-1 ended]")))
        #expect(fixture.updates.contains(.submitPrompt("[job-2 ended]")), "no thread-9: main is told")
    }
}
