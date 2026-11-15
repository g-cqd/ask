internal import AskMCP

/// The process that hosts a script's VM, as its keeper holds it: its messages in, a message out, and its end. A test gives a
/// host that runs in the test's own process, or one that never answers.
struct CodemodeChild: Sendable {
    /// What starts a child that may take `memoryMiB` of memory; nil when it could not be started.
    typealias Start = @Sendable (_ memoryMiB: Int) async -> CodemodeChild?

    /// The child's messages, one a line, without their line ends.
    let incoming: AsyncStream<[UInt8]>
    /// Sends one message, without a line end.
    let send: @Sendable ([UInt8]) async throws -> Void
    /// Ends the child, and returns its exit status when it exited by itself.
    let close: @Sendable () async -> Int32?

    /// `executable codemode`, a child of this process (ADR-0156): ask itself, hosting the VM. It gets no environment: it reads
    /// none, and a script has no way to read one. Told to leave, it has a fifth of a second before it is stopped: a script
    /// that spins does not hear.
    static func process(_ executable: String) -> Start {
        { memoryMiB in
            let launch = StdioLaunch(
                executable: executable,
                arguments: ["codemode", "--memory", "\(memoryMiB)"],
                inheriting: [:]
            )
            let transport = StdioTransport(launch, grace: .milliseconds(200))
            guard await transport.waitUntilRunning() != nil else { return nil }
            return CodemodeChild(
                incoming: transport.incoming,
                send: { try await transport.send($0) },
                close: {
                    await transport.close()
                    guard case .exited(let status) = transport.exit else { return nil }
                    return Int32(status)
                }
            )
        }
    }
}
