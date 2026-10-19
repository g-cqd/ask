internal import Foundation
internal import Synchronization
internal import Testing

@testable import AskAI

/// The runner on a flow that is not a key flow: a server-chosen interval that can be told to slow down, a grant of two
/// values, instructions beside the link, and an outcome that is not a key. Codex's device-code sign-in is that flow.
@Suite("The runner waits on the server's interval, slows when told, and returns whatever the flow ends in")
struct SignInRunnerTests {
    /// A flow whose polls are scripted.
    struct Scripted: BrowserSignIn {
        let script: [SignInPoll<[String]>]
        let interval: Duration
        let pollsImmediately = false
        let polled = Counter()

        final class Counter: Sendable {
            private let count = Mutex<Int>(0)
            func next() -> Int {
                count.withLock { value in
                    defer { value += 1 }
                    return value
                }
            }
        }

        func start() async throws(SignInError) -> SignInStart<String> {
            SignInStart(
                session: "s", url: URL(string: "https://example.test/device")!, window: .seconds(600),
                interval: interval, instructions: "Enter ABCD-1234")
        }

        func poll(_ session: String) async throws(SignInError) -> SignInPoll<[String]> {
            script[Swift.min(polled.next(), script.count - 1)]
        }

        func finish(_ session: String, grant: [String]) async throws(SignInError) -> String {
            grant.joined(separator: "+")
        }
    }

    private func run(_ flow: Scripted, clock: StepClock = StepClock()) async throws -> (
        outcome: String, prompts: [SignInPrompt], clock: StepClock
    ) {
        let prompts = PromptLog()
        let outcome = try await SignInRunner(clock: clock).run(flow) { prompts.add($0) }
        return (outcome, prompts.all, clock)
    }

    @Test func `the flow's own interval is waited between polls, and its outcome is returned as it is`() async throws {
        let done = try await run(
            Scripted(script: [.pending, .pending, .complete(["code", "verifier"])], interval: .seconds(4)))
        #expect(done.outcome == "code+verifier")
        #expect(done.clock.sleeps == [.seconds(4), .seconds(4), .seconds(4)])
    }

    @Test func `each slow down adds five seconds to every wait after it`() async throws {
        let done = try await run(
            Scripted(script: [.pending, .slowDown, .slowDown, .complete(["x"])], interval: .seconds(2)))
        #expect(done.clock.sleeps == [.seconds(2), .seconds(2), .seconds(7), .seconds(12)])
    }

    @Test func `the link and the instructions beside it are shown together`() async throws {
        let done = try await run(Scripted(script: [.complete(["x"])], interval: .seconds(1)))
        #expect(
            done.prompts == [
                SignInPrompt(url: URL(string: "https://example.test/device")!, instructions: "Enter ABCD-1234")
            ])
    }
}
