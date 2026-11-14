import Foundation

/// The targets, by the name `ASK_FUZZ_TARGET` gives. Each takes the fuzzer's bytes and returns; a crash, a trap or a broken
/// property (``broken(_:)``) is a finding.
let targets: [String: @Sendable ([UInt8]) -> Void] = [
    "sse": fuzzSSE, "session": fuzzSession, "mcp": fuzzMCP, "terminal": fuzzTerminal, "index": fuzzIndex,
    "text": fuzzText
]

private let chosen: @Sendable ([UInt8]) -> Void = {
    let name = ProcessInfo.processInfo.environment["ASK_FUZZ_TARGET"] ?? ""
    guard let target = targets[name] else {
        FileHandle.standardError.write(
            Data("ASK_FUZZ_TARGET must be one of: \(targets.keys.sorted().joined(separator: ", "))\n".utf8)
        )
        exit(2)
    }
    return target
}()

/// A property the code promises did not hold for this input: stops the run as a crash does, with what broke.
func broken(_ what: String) -> Never {
    fatalError("PROPERTY BROKEN: \(what)")
}

/// `bytes` cut into pieces whose sizes the bytes themselves choose, so the fuzzer explores where a stream is cut.
func pieces(of bytes: ArraySlice<UInt8>, seed: UInt8) -> [[UInt8]] {
    var pieces: [[UInt8]] = []
    var rest = bytes
    var size = Int(seed % 31) + 1
    while !rest.isEmpty {
        pieces.append(Array(rest.prefix(size)))
        rest = rest.dropFirst(size)
        size = (size * 7 + 3) % 61 + 1
    }
    return pieces
}

@_cdecl("LLVMFuzzerTestOneInput")
public func fuzzOne(_ data: UnsafePointer<UInt8>?, _ size: Int) -> CInt {
    chosen(Array(UnsafeBufferPointer(start: data, count: size)))
    return 0
}
