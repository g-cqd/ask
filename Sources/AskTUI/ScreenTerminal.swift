internal import TerminalKitIO
internal import TerminalKitInput
internal import TerminalKitRender

/// What the screen draws on and with: the terminal, its mode session, the thread that draws frames, and what it drew last.
struct ScreenTerminal {
    let connection: any TerminalConnection
    let session: TerminalSession
    let renderer: RenderLoop<ScreenComposer>
    let frames: FrameBox
    let clipboard: ScreenClipboard
    /// Whether the environment says the terminal may draw kitty graphics (roadmap 0208), so it is asked.
    var mayDrawImages = false
    /// Whether the terminal reads OSC 9;4 as progress (note n59), so it is sent.
    var readsProgress = false
    /// How a notification reaches the person (`ui.notify`, note n62).
    var notification = TerminalNotification(style: .off, environment: [:])
}

/// The modes the screen asks the terminal for: the full-screen set, with the mouse reported unless `options` turn it off.
func modes(for options: ScreenOptions) -> TerminalModes {
    var modes = TerminalModes.fullScreen
    modes.mouse = options.mouse
    modes.mouseMotion = options.mouse && options.hover
    // Focus decides whether to notify (note n62): asked for only while notifications are on.
    modes.focusEvents = options.notify != .off
    return modes
}

/// A render loop drawing the screen at the terminal's size. It idles until the first state is submitted.
func makeRenderer(
    on connection: any TerminalConnection,
    frames: FrameBox
) throws -> RenderLoop<ScreenComposer> {
    let size = try connection.getSize()
    return RenderLoop(
        connection: connection,
        columns: size.columns,
        rows: size.rows,
        composer: ScreenComposer(frames: frames)
    )
}
