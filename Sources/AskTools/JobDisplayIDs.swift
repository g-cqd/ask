internal import Foundation

/// Process-local display identities are never reused, including after a job ends.
struct JobDisplayIDs {
    private var used: Set<String> = []

    mutating func next(candidate: UInt16 = .random(in: .min ... .max)) -> String {
        if used.count < 65_536 {
            var value = candidate
            while true {
                let hex = String(value, radix: 16)
                let id = String(repeating: "0", count: 4 - hex.count) + hex
                if used.insert(id).inserted { return id }
                value &+= 1
            }
        }
        // A process that exhausted four hex digits gets UUIDs, never ambiguous recycled labels.
        while true {
            let id = UUID().uuidString.lowercased()
            if used.insert(id).inserted { return id }
        }
    }
}
