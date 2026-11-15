internal import AemiJSONRPC
internal import AemiRuntime
internal import System

extension ACPServer {
    /// Serves the client on the process's standard input and output, as an editor runs an agent, until the input ends. Standard
    /// input is read a block at a time on a thread of its own, so a read that waits holds none of the threads tasks run on.
    package static func serveStandardStreams(
        agent: ACPImplementation,
        sessions: ACPSession.Source? = nil,
        load: ACPSession.Loader? = nil
    ) async {
        let reader = BlockingOffloadPool(width: 1)
        let server = ACPServer(output: DescriptorSink(.standardOutput), agent: agent, sessions: sessions, load: load)
        await server.run(
            reading: FileDescriptorChunks(descriptor: FileDescriptor.standardInput.rawValue, pool: reader)
        )
        reader.shutdown()
    }
}
