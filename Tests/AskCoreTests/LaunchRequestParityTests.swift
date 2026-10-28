internal import Foundation
internal import Testing

/// A bare `ask` skips ArgumentParser and runs `LaunchRequest()` (ADR-0065). That is only the same launch as a parsed
/// empty command line while every option's default is "not given". The executable has no test target, so this reads
/// the two source files: each `@Option` and `@Flag` in `Ask` is optional or `false`, and `LaunchRequest` declares the
/// same property with the same default. Adding an option with another default, or forgetting to mirror one, fails here.
@Suite("A bare launch and an empty command line are the same launch")
struct LaunchRequestParityTests {
    private struct Property: Equatable {
        let name: String
        let type: String
        let defaultValue: String
    }

    private static func properties(in file: String, attributed: Bool) throws -> [Property] {
        let text = try String(
            contentsOf: SourceStandards.repositoryRoot.appending(path: file), encoding: .utf8)
        var found: [Property] = []
        var pending = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("    @Flag") || line.hasPrefix("    @Option") { pending = true }
            guard line.hasPrefix("    var "), pending || !attributed else { continue }
            pending = false
            let declaration = line.dropFirst("    var ".count)
            let parts = declaration.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let named = parts[0].split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let type =
                named.count > 1 ? named[1] : (parts.count > 1 && ["false", "true"].contains(parts[1]) ? "Bool" : "?")
            found.append(Property(name: named[0], type: type, defaultValue: parts.count > 1 ? parts[1] : "nil"))
        }
        return found
    }

    @Test func `every parsed option defaults to not given`() throws {
        let options = try Self.properties(in: "Sources/ask/Ask.swift", attributed: true)
        #expect(options.count >= 15, "the scan must actually find the options: \(options.count)")
        for option in options {
            let notGiven =
                (option.type.hasSuffix("?") && option.defaultValue == "nil") || option.defaultValue == "false"
                || (option.type.hasPrefix("[") && option.defaultValue == "[]")
            #expect(notGiven, "\(option.name) defaults to \(option.defaultValue); a bare launch would not match it")
        }
    }

    @Test func `the launch request declares every option with the same default`() throws {
        let options = try Self.properties(in: "Sources/ask/Ask.swift", attributed: true)
        let request = try Self.properties(in: "Sources/ask/LaunchRequest.swift", attributed: false)
        #expect(Set(options.map(\.name)) == Set(request.map(\.name)))
        for option in options {
            #expect(request.contains(option), "\(option.name) differs between Ask and LaunchRequest")
        }
    }
}
