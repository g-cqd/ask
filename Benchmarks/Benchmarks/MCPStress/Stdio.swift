import AskAI
import AskMCP
import Foundation

/// A fake server to run on standard input and output.
struct StdioServer {
    var name: String
    var executable: String
    var arguments: [String]

    var launch: StdioLaunch {
        StdioLaunch(executable: executable, arguments: arguments, inheriting: ProcessInfo.processInfo.environment)
    }
}

/// `calls` echo calls through ask's stdio transport and connection, `concurrency` in flight.
func stdioThroughAsk(_ server: StdioServer, calls: Int, size: Int, concurrency: Int) async throws -> Duration {
    let connection = MCPConnection(transport: StdioTransport(server.launch), clientName: "stress", clientVersion: "1")
    _ = try await connection.start()
    _ = try await callMany(connection, calls: 1, size: size, concurrency: 1)  // the server has warmed its reply
    let elapsed = try await callMany(connection, calls: calls, size: size, concurrency: concurrency)
    await connection.close()
    return elapsed
}

/// The floor for a stdio server: the same child, written to and read from with blocking system calls, one parse an answer, nothing else.
func stdioFloor(_ server: StdioServer, calls: Int, size: Int) throws -> Duration {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: try resolve(server.executable))
    process.arguments = server.arguments
    let input = Pipe()
    let output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    try process.run()
    defer {
        try? input.fileHandleForWriting.close()
        process.waitUntilExit()
    }
    let writing = input.fileHandleForWriting.fileDescriptor
    var reader = LineReader(descriptor: output.fileHandleForReading.fileDescriptor)
    func call(_ bytes: [UInt8]) -> [UInt8] {
        let line = bytes + [10]
        line.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                offset += Swift.max(0, write(writing, buffer.baseAddress! + offset, buffer.count - offset))
            }
        }
        return reader.next() ?? []
    }
    _ = call(Array(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#.utf8))
    _ = call(Payloads.request(id: 2, size: size))
    var total = 0
    let elapsed = ContinuousClock()
        .measure {
            for id in 3 ..< (3 + calls) {
                total &+= Payloads.text(of: call(Payloads.request(id: id, size: size)))?.utf8.count ?? -1_000_000
            }
        }
    guard total == calls * size else { throw StressFailure.wrongAnswer }
    return elapsed
}

/// Lines from a descriptor, read in large blocks.
struct LineReader {
    let descriptor: Int32
    private var buffer: [UInt8] = []
    private var start = 0

    init(descriptor: Int32) { self.descriptor = descriptor }

    mutating func next() -> [UInt8]? {
        var searched = start
        while true {
            if let end = buffer[searched...].firstIndex(of: 10) {
                let line = Array(buffer[start ..< end])
                start = end + 1
                if start > 1 << 20 {
                    buffer.removeFirst(start)
                    start = 0
                }
                return line
            }
            searched = buffer.count
            var chunk = [UInt8](repeating: 0, count: 1 << 16)
            let count = chunk.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            guard count > 0 else { return nil }
            buffer += chunk[0 ..< count]
        }
    }
}

/// A program's path, looking it up on `PATH` when it is a bare name.
func resolve(_ executable: String) throws -> String {
    if executable.contains("/") { return executable }
    for directory in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
        let path = "\(directory)/\(executable)"
        if FileManager.default.isExecutableFile(atPath: path) { return path }
    }
    throw StressFailure.serverDidNotStart(executable)
}
