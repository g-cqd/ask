internal import Darwin

/// Closes a descriptor when the last holder lets it go: a viewer's terminal is closed once its mirror is gone, so the descriptor is never
/// closed while a render thread may still write to it, nor reused under it.
final class DescriptorCloser: Sendable {
    private let descriptor: Int32

    init(_ descriptor: Int32) { self.descriptor = descriptor }

    deinit { close(descriptor) }
}
