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
}

/// The modes the screen asks the terminal for: the full-screen set, with the mouse reported unless `options` turn it off.
func modes(for options: ScreenOptions) -> TerminalModes {
    var modes = TerminalModes.fullScreen
    modes.mouse = options.mouse
    return modes
}

/// A render loop drawing the screen at the terminal's size. It idles until the first state is submitted.
func makeRenderer(
    on connection: any TerminalConnection, frames: FrameBox
) throws -> RenderLoop<ScreenComposer> {
    let size = try connection.getSize()
    return RenderLoop(
        connection: connection, columns: size.columns, rows: size.rows, composer: ScreenComposer(frames: frames))
}
