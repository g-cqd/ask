internal import Foundation
internal import TerminalKitCodecs
internal import TerminalKitIO
internal import Testing

@testable import AskTUI

/// The screen asks the terminal for mouse reports when `ScreenOptions` say so, and gives them up on exit.
@Suite("The screen asks for the mouse only when told to")
struct ScreenMouseModeTests {
    private func connectionOutput(options: ScreenOptions) async throws -> String {
        let connection = MockTerminalConnection()
        let (resizes, done) = AsyncStream<Void>.makeStream()
        done.finish()
        struct Idle: Conversation {
            func start(_ prompt: String, update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never>
            {
                Task { update(.runEnded) }
            }
        }
        // Control-D at an empty prompt ends the screen.
        connection.feedInput([0x04])
        _ = try await runInteractiveScreen(
            on: connection, conversation: Idle(), label: "m", options: options, resizes: resizes)
        return String(decoding: connection.writtenOutput, as: UTF8.self)
    }

    @Test func `the screen asks for mouse reports and gives them up again`() async throws {
        let output = try await connectionOutput(options: ScreenOptions(prompt: "ask> ", tint: false, separator: false))
        let enable = String(decoding: EscapeSequences.enableMouseSGR, as: UTF8.self)
        let disable = String(decoding: EscapeSequences.disableMouseSGR, as: UTF8.self)
        #expect(output.contains(enable))
        #expect(output.contains(disable))
        #expect(output.range(of: enable)!.lowerBound < output.range(of: disable)!.lowerBound)
    }

    @Test func `with the mouse off the terminal is never asked to report it`() async throws {
        let output = try await connectionOutput(
            options: ScreenOptions(mouse: false, prompt: "ask> ", tint: false, separator: false))
        #expect(!output.contains(String(decoding: EscapeSequences.enableMouseSGR, as: UTF8.self)))
    }
}
