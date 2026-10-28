import Foundation

// MCP calls under stress (roadmap 0114). Each layer is measured against the floor beneath it:
//   codec      writing the request and reading the answer's text, nothing else
//   loopback   ask's connection with an in-process server (floor: codec + the server's own cost)
//   stdio      ask's transport and connection with real child processes (floor: a bare client of the same child)
//   http       ask's transport and connection over HTTP (floor: the same HTTP stack, one parse an answer)
// Usage: swift run -c release MCPStress [scale]   (scale multiplies every call count; 1 by default)

setvbuf(stdout, nil, _IONBF, 0)
let scale = CommandLine.arguments.dropFirst().first.flatMap(Double.init) ?? 1
func count(_ base: Int) -> Int { Swift.max(1, Int(Double(base) * scale)) }
let servers = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("MCPServers").path
let fakeC = NSTemporaryDirectory() + "mcp-fake-c"

func compileC() throws {
    let cc = Process()
    cc.executableURL = URL(fileURLWithPath: "/usr/bin/cc")
    cc.arguments = ["-O2", "-o", fakeC, servers + "/stdio_server.c"]
    try cc.run()
    cc.waitUntilExit()
    guard cc.terminationStatus == 0 else { throw StressFailure.serverDidNotStart("cc") }
}

func report(_ measurement: Measurement) { print(measurement.line) }

print("case".padding(toLength: 46, withPad: " ", startingAt: 0) + "per call".leftPadded(11) + "rate".leftPadded(10))
for size in Payloads.sizes {
    let calls = count(size < 1000 ? 1_000_000 : size < 100_000 ? 100_000 : 2_000)
    let codec = codecFloor(calls: calls, size: size)
    report(Measurement(name: "codec \(size) B", calls: calls, elapsed: codec))
    let server = serverCost(calls: calls, size: size)
    report(Measurement(name: "loopback server alone \(size) B", calls: calls, elapsed: server))
    for concurrency in [1, 64] {
        let elapsed = try await loopback(calls: calls, size: size, concurrency: concurrency)
        report(
            Measurement(
                name: "loopback \(size) B, \(concurrency) in flight", calls: calls, elapsed: elapsed,
                floor: codec + server))
    }
}

try compileC()
let stdioServers = [
    StdioServer(name: "C", executable: fakeC, arguments: []),
    StdioServer(name: "Python", executable: "python3", arguments: [servers + "/stdio_server.py"]),
    StdioServer(name: "Node", executable: "node", arguments: [servers + "/stdio_server.mjs"]),
    StdioServer(name: "Bun", executable: "bun", arguments: [servers + "/stdio_server.mjs"])
]
for server in stdioServers {
    for size in Payloads.sizes {
        let calls = count(size < 100_000 ? 20_000 : 500)
        let floor = try stdioFloor(server, calls: calls, size: size)
        let elapsed = try await stdioThroughAsk(server, calls: calls, size: size, concurrency: 1)
        report(Measurement(name: "stdio \(server.name) \(size) B", calls: calls, elapsed: elapsed, floor: floor))
    }
    let calls = count(20_000)
    let parallel = try await stdioThroughAsk(server, calls: calls, size: 2, concurrency: 16)
    report(Measurement(name: "stdio \(server.name) 2 B, 16 in flight", calls: calls, elapsed: parallel))
}

let httpServers = [
    ("Node JSON", "node", "json", false), ("Node SSE", "node", "sse", true), ("Bun JSON", "bun", "json", false)
]
for (index, (name, runtime, mode, sse)) in httpServers.enumerated() {
    let server = try HTTPServer(
        name: name, runtime: runtime, script: servers + "/http_server.mjs", port: 18_700 + index, mode: mode)
    defer { server.stop() }
    for size in [2, 4096] {
        let calls = count(3_000)
        let floor = try await httpFloor(server, calls: calls, size: size, sse: sse)
        let elapsed = try await httpThroughAsk(server, calls: calls, size: size, concurrency: 1)
        report(Measurement(name: "http \(name) \(size) B", calls: calls, elapsed: elapsed, floor: floor))
    }
}
