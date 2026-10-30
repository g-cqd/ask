internal import Testing

@testable import AskCore

/// The shape of the source tree, made mechanical.
///
/// A file listing is the cheapest map of a codebase, and it is only a map while a file holds what its name
/// says. The first audit found 30 of 70 files declaring several types, some of them five, so the listing
/// hid most of the types the project owns. Each rule here is a source scan because no compiler setting can
/// say "this file's name must be its type's name".
@Suite("The source tree's structure is enforced, not requested")
struct SourceStructureTests {
    // MARK: - The scanner, on synthetic text

    @Test func `a file named for its only type is clean`() {
        let text = "struct Tool {\n    var name: String\n}\n"
        #expect(SourceStructure.violations(fileName: "Tool.swift", text: text).isEmpty)
    }

    @Test func `a file declaring two types is reported`() {
        let text = "struct Tool {}\nenum ToolError {}\n"
        let found = SourceStructure.violations(fileName: "Tool.swift", text: text)
        #expect(found.count == 1)
        #expect(found.first?.contains("ToolError") == true)
    }

    @Test func `a private type still counts, because it is still a type the listing hides`() {
        let text = "struct Tool {}\nprivate struct Helper {}\n"
        #expect(SourceStructure.violations(fileName: "Tool.swift", text: text).count == 1)
    }

    @Test func `a file whose name differs from its only type is reported`() {
        let text = "struct Tool {}\n"
        let found = SourceStructure.violations(fileName: "Tools.swift", text: text)
        #expect(found.count == 1)
        #expect(found.first?.contains("Tool") == true)
    }

    @Test func `a nested type does not count as a second type`() {
        let text = "struct Tool {\n    enum Kind {}\n    struct Output {}\n}\n"
        #expect(SourceStructure.violations(fileName: "Tool.swift", text: text).isEmpty)
    }

    @Test func `every modifier and attribute before the keyword is read through`() {
        let text = "@available(macOS 26, *)\npublic final class Tool {}\n"
        #expect(SourceStructure.declarations(in: text).map(\.name) == ["Tool"])
        let single = "@MainActor public indirect enum Tree {}\n"
        #expect(SourceStructure.declarations(in: single).map(\.name) == ["Tree"])
    }

    @Test func `an extension of the file's own type is clean`() {
        let text = "struct Tool {}\nextension Tool: Sendable {}\nextension Tool.Kind {}\n"
        #expect(SourceStructure.violations(fileName: "Tool.swift", text: text).isEmpty)
    }

    @Test func `an extension of another type inside a type's file is reported`() {
        let text = "struct Tool {}\nextension String {}\n"
        let found = SourceStructure.violations(fileName: "Tool.swift", text: text)
        #expect(found.count == 1)
        #expect(found.first?.contains("String") == true)
    }

    @Test func `a foreign extension whose members are all private is a helper, not a concept`() {
        let text = """
            struct Tool {}

            extension UInt8 {
                /// A continuation byte.
                fileprivate static let newline: UInt8 = 0x0A
                fileprivate var isContinuation: Bool { self & 0xC0 == 0x80 }
                @inline(__always)
                private func mask() -> UInt8 { self }
            }
            """
        #expect(SourceStructure.violations(fileName: "Tool.swift", text: text).isEmpty)
    }

    @Test func `one internal member makes a foreign extension a concept that needs its own file`() {
        let text = """
            struct Tool {}

            extension UInt8 {
                fileprivate static let newline: UInt8 = 0x0A
                var isContinuation: Bool { self & 0xC0 == 0x80 }
            }
            """
        let found = SourceStructure.violations(fileName: "Tool.swift", text: text)
        #expect(found.count == 1)
        #expect(found.first?.contains("UInt8") == true)
    }

    @Test func `a file of extensions is named Base plus Topic`() {
        let text = "extension String {}\n"
        #expect(SourceStructure.violations(fileName: "String+Hex.swift", text: text).isEmpty)
        #expect(SourceStructure.violations(fileName: "Hex.swift", text: text).count == 1)
    }

    @Test func `a file of extensions to two types is reported`() {
        let text = "extension String {}\nextension Int {}\n"
        #expect(SourceStructure.violations(fileName: "String+Hex.swift", text: text).count == 1)
    }

    @Test func `an extension of a sugared array is an extension of Array`() {
        let text = "extension [UInt8] {}\n"
        #expect(SourceStructure.violations(fileName: "Array+Bytes.swift", text: text).isEmpty)
    }

    @Test func `a file with no type, such as free functions, may have any name`() {
        #expect(SourceStructure.violations(fileName: "PrintRun.swift", text: "func run() {}\nlet x = 1\n").isEmpty)
    }

    @Test func `text in a multi-line string or a comment is not a declaration`() {
        let text = """
            // struct Commented {}
            let sample = \"\"\"
            struct InsideString {}
            \"\"\"
            struct Real {}
            """
        #expect(SourceStructure.declarations(in: text).map(\.name) == ["Real"])
    }

    @Test func `an indented declaration is nested and is not read`() {
        #expect(SourceStructure.declarations(in: "struct A {\n    struct B {}\n}\n").map(\.name) == ["A"])
    }

    @Test func `the line count is the number of lines, not of newlines`() {
        #expect(SourceStructure.lineCount("a\nb\n") == 2)
        #expect(SourceStructure.lineCount("a\nb") == 2)
        #expect(SourceStructure.lineCount("") == 0)
    }

    // MARK: - The repository

    @Test func `every source file declares at most one type, named for it`() throws {
        let offenders = try SourceStructure.violations(in: SourceStandards.sources)
        #expect(
            offenders.isEmpty,
            """
            Give each type its own file, named for the type. Extensions go beside their type, or in \
            `Base+Topic.swift`. Nest a type that only one other type uses.
            \(offenders.joined(separator: "\n"))
            """
        )
    }

    @Test func `every test file declares at most one type, named for it`() throws {
        let offenders = try SourceStructure.violations(in: SourceStandards.tests)
        #expect(
            offenders.isEmpty,
            """
            One suite per file, named for the suite. Nest a double used by one suite inside it; a double \
            several suites share is a type of its own, in its own file.
            \(offenders.joined(separator: "\n"))
            """
        )
    }

    @Test func `no file outgrows the ceiling`() throws {
        let offenders = try SourceStructure.overlongFiles(in: SourceStandards.sources + SourceStandards.tests)
        #expect(
            offenders.isEmpty,
            """
            A file past \(SourceStructure.lineCeiling) lines holds more than one idea. Split it by behaviour.
            \(offenders.joined(separator: "\n"))
            """
        )
    }
}
