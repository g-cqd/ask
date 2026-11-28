internal import AemiMCP
internal import AskCodemode
internal import Darwin

/// The process that hosts a script's VM, as its keeper holds it: its messages in, a message out, and its end. A test gives a
/// host that runs in the test's own process, or one that never answers.
struct CodemodeChild: Sendable {
    /// A child's memory as its keeper sees it from outside, for a child that cannot be relied on to watch itself.
    struct Memory: Sendable {
        /// What the child has taken, in bytes; 0 when unknown.
        let footprint: @Sendable () -> Int
        /// Ends the child at once, without a word to it.
        let stop: @Sendable () -> Void
    }

    /// What starts a child that may take `memoryMiB` of memory; nil when it could not be started.
    typealias Start = @Sendable (_ memoryMiB: Int) async -> CodemodeChild?

    /// The child's messages, one a line, without their line ends.
    let incoming: AsyncStream<[UInt8]>
    /// Sends one message, without a line end.
    let send: @Sendable ([UInt8]) async throws -> Void
    /// Ends the child, and returns its exit status when it exited by itself.
    let close: @Sendable () async -> Int32?
    /// Set for a child its keeper is to watch (``CodemodeWatch``); nil for one that watches itself.
    var memory: Memory?

    /// `executable codemode`, a child of this process (ADR-0156): ask itself, hosting the VM. It gets no environment: it reads
    /// none, and a script has no way to read one. Told to leave, it has a fifth of a second before it is stopped: a script
    /// that spins does not hear.
    static func process(_ executable: String) -> Start {
        { memoryMiB in
            await launched(
                StdioLaunch(
                    executable: executable,
                    arguments: ["codemode", "--memory", "\(memoryMiB)"],
                    inheriting: [:]
                )
            )
        }
    }

    /// The child `launch` starts, once it runs; nil when it could not be started. `watched`, its keeper watches its memory.
    static func launched(_ launch: StdioLaunch, watched: Bool = false) async -> CodemodeChild? {
        let transport = StdioTransport(launch, grace: .milliseconds(200))
        guard let pid = await transport.waitUntilRunning() else { return nil }
        // A process is its id and when it started: once this one is gone its id may be another's, which is not to be stopped.
        let started = CodemodeMemory.usage(of: pid)?.started
        let memory = Memory(
            footprint: {
                guard let usage = CodemodeMemory.usage(of: pid), usage.started == started else { return 0 }
                return usage.footprint
            },
            stop: { kill(pid, SIGKILL) }
        )
        return CodemodeChild(
            incoming: transport.incoming,
            send: { try await transport.send($0) },
            close: {
                await transport.close()
                guard case .exited(let status) = transport.exit else { return nil }
                return Int32(status)
            },
            memory: watched ? memory : nil
        )
    }
}
