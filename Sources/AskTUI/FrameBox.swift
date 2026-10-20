internal import Synchronization

/// Hands the newest frame's geometry from the render thread, which draws it, to the loop that handles the mouse.
///
/// A click means what the user saw, so it is resolved against the frame that was drawn, not the state that has moved on since.
/// Positions are anchored in content, so a frame or two of lag changes nothing.
final class FrameBox: Sendable {
    private let latest = Mutex(FrameGeometry())

    func store(_ frame: FrameGeometry) { latest.withLock { $0 = frame } }
    func load() -> FrameGeometry { latest.withLock { $0 } }
}
