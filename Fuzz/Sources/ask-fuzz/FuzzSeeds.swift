import AemiSearch
import Foundation
import System

@testable import AskAgentCore

/// Seeds that cannot be written by hand: a framed (compressed) session and a search index, made by the code that writes them. When
/// `ASK_FUZZ_SEEDS` names a directory, libFuzzer's start writes the chosen target's there (`Scripts/fuzz.sh` gives the corpus).
func writeGeneratedSeeds() {
    let environment = ProcessInfo.processInfo.environment
    guard let directory = environment["ASK_FUZZ_SEEDS"] else { return }
    switch environment["ASK_FUZZ_TARGET"] {
        case "session":
            let path = directory + "/seed-framed-\(getpid()).tmp"
            defer { try? FileManager.default.removeItem(atPath: path) }
            guard
                let file = try? SessionFile.create(
                    at: FilePath(path),
                    format: SessionFormat(compressed: true, encrypted: false)
                )
            else { return }
            let session = SessionRecorder(file)
            _ = try? session.append(.user("why is the cache key wrong"))
            _ = try? session.append(.toolResult(callID: "c", content: "error: no such module", isError: true))
            if let bytes = FileManager.default.contents(atPath: path) {
                try? bytes.write(to: URL(fileURLWithPath: directory + "/seed-framed"))
            }
        case "index":
            let index = SearchIndex()
            index.add(
                SearchDocument(
                    text: "The cache key is the request's URL.",
                    fields: ["kind": "reply", "entry": "1"],
                    time: 10
                )
            )
            index.add(
                SearchDocument(
                    text: "error: no such file: Package.resolved",
                    fields: ["kind": "tool", "entry": "2"],
                    time: 20
                )
            )
            try? Data(index.serialized()).write(to: URL(fileURLWithPath: directory + "/seed-index"))
        default:
            break
    }
}

@_cdecl("LLVMFuzzerInitialize")
public func fuzzInitialize(_ count: UnsafeMutablePointer<CInt>?, _ arguments: UnsafeMutableRawPointer?) -> CInt {
    writeGeneratedSeeds()
    return 0
}
