internal import Darwin
internal import TerminalKitIO

/// The process's screen, as the gateway's viewer endpoint reaches it (ADR-0170): a viewer is the replica side of a pseudo-terminal,
/// attached as a mirror of the running screen.
public enum ScreenViewers {
    /// Whether a screen is running in this process to be viewed.
    public static var isRunning: Bool { ScreenMirrors.process.isRunning }

    /// Attaches the pseudo-terminal replica `descriptor` as a viewer of the running screen; its id, or nil when no screen runs. The
    /// viewer owns the descriptor from here, and closes it once the screen lets it go, attached or not.
    public static func attach(replica descriptor: Int32) -> Int? {
        ScreenMirrors.process.attach(POSIXTerminalConnection(fileDescriptor: descriptor), closing: descriptor)
    }

    /// Viewer `id`'s terminal changed size: its pseudo-terminal's window size is already set.
    public static func resized(_ id: Int) { ScreenMirrors.process.resized(id) }

    /// Viewer `id` goes away.
    public static func detach(_ id: Int) { ScreenMirrors.process.detach(id) }
}
