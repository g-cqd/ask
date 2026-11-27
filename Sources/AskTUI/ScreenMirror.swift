internal import Synchronization
internal import TerminalKitIO
internal import TerminalKitInput
internal import TerminalKitRender

/// A second terminal showing a running screen (ADR-0170): the gateway's viewer. It is drawn from the same state as the screen, at its
/// own size, by a render loop of its own; its keys and pastes go to the same screen, as the person's do. Mouse reports are not asked
/// for and, if sent, not taken: a click means a place in the screen's own frame, not the mirror's.
final class ScreenMirror: Sendable {
    let id: Int
    let connection: SerializedConnection
    let session: TerminalSession
    let renderer: RenderLoop<ScreenComposer>
    let input: InputSource
    /// Closes the terminal's descriptor once the mirror is gone, when the mirror owns it.
    private let closer: DescriptorCloser?

    /// A mirror on `connection`, whose size it is drawn at; `closer` closes the descriptor it owns once the mirror is gone.
    init(id: Int, connection: any TerminalConnection, closer: DescriptorCloser? = nil) throws {
        self.id = id
        self.closer = closer
        let serialized = SerializedConnection(connection)
        self.connection = serialized
        var modes = TerminalModes.fullScreen
        modes.mouse = false
        modes.mouseMotion = false
        modes.focusEvents = false
        session = TerminalSession(connection: serialized, modes: modes, keyboardProtocol: .unsupported)
        renderer = try makeRenderer(on: serialized, frames: FrameBox())
        input = InputSource(connection: serialized)
    }

    /// Whether an input event from the mirror is the person's to apply: keys and pastes; not the pointer, focus or a resize report.
    static func takes(_ event: InputEvent) -> Bool {
        switch event {
            case .key, .paste: true
            case .mouse, .resize, .focusIn, .focusOut, .refresh, .overflow, .unknown: false
        }
    }
}
