import Testing

@testable import AskTUI

@Suite("Queued steering notice replaced by user prompt in transcript")
struct QueuedSteeringReplacementTests {
    @Test func `acceptance replaces by prompt ID even for identical queued text`() {
        var controller = ScreenController(label: "test")
        _ = controller.begin(.startRun("initial"))
        _ = controller.queue("same", followUp: false)
        _ = controller.queue("same", followUp: true)
        controller.handle(.promptAccepted(id: 0, text: "same"))
        #expect(
            controller.state.transcript.items == [
                .user("same"), .notice("Queued follow-up: same", isError: false)
            ])
    }

    @Test func `a prompt restarted after the final boundary replaces its placeholder`() {
        var controller = ScreenController(label: "test")
        _ = controller.begin(.startRun("initial"))
        _ = controller.queue("late", followUp: false)
        #expect(controller.handle(.runEnded) == [.startRun("late")])
        #expect(controller.state.transcript.items == [.user("late")])
    }

    @Test func `promptAccepted replaces queued notice with user prompt without duplicating text`() {
        var controller = ScreenController(label: "test")
        controller.state.running = true
        _ = controller.begin(.startRun("initial"))

        // User queues steering while running
        _ = controller.queue("next action", followUp: false)
        #expect(controller.state.transcript.items.count == 1)
        #expect(controller.state.transcript.items[0] == .notice("Queued steering: next action", isError: false))

        // Prompt accepted by loop
        controller.handle(.promptAccepted(id: 0, text: "next action"))
        #expect(controller.state.transcript.items.count == 1)
        #expect(controller.state.transcript.items[0] == .user("next action"))
    }
}
