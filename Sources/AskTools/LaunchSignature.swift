/// The running build's signature, read once near launch (roadmap 0153). `/reload` compares a new build against it, and a new build
/// replaces the running one's file: read at reload time, the signature would be the new build's. The read costs a few milliseconds,
/// so it runs off the launch path; a reload waits for it.
public enum LaunchSignature {
    private static let reading = Task.detached(priority: .utility) { BuildSignature.readRunning() }

    /// Starts the read. Call it at launch; without it, the read happens at the first reload, and a file replaced by then is refused.
    public static func start() { _ = reading }

    /// The signature as read at launch.
    public static var running: BuildSignature.Running {
        get async { await reading.value }
    }
}
