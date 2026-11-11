internal import Foundation
internal import Testing

@testable import AskTUI

/// A path whose `:line` is drawn on the next row, because the row wrapped there, still clicks with its line (the owner, 2026-11-11).
@Suite("A wrapped path keeps its line")
struct WrappedLinkPlaceTests {
    private static let path = "/w/proj/Sources/AVeryLongFileNameThatWraps.swift"

    private func rig(_ updates: [ConversationUpdate], columns: Int) -> PointerRig {
        var options = ScreenOptions.legacy
        options.workspace = "/elsewhere"
        options.home = "/Users/me"
        options.foldTools = false
        var rig = PointerRig(columns: columns, rows: 20, options: options)
        rig.controller.state.blocks.paths?.exists = { _ in true }
        for update in updates { rig.controller.handle(update) }
        rig.draw()
        return rig
    }

    /// What a click on each linked cell opens, by row.
    private func targets(_ rig: PointerRig) -> [String] {
        var found: [String] = []
        for row in 0 ..< 20 where rig.controller.frame.links.indices.contains(row) {
            for link in rig.controller.frame.links[row] where !found.contains(link.target) { found.append(link.target) }
        }
        return found
    }

    @Test(arguments: [44, 50, 52, 56])
    func `in a reply`(columns: Int) {
        let rig = rig([.assistantText("See \(Self.path):12:5 now.")], columns: columns)
        #expect(targets(rig) == ["file://\(Self.path)#L12C5"], "\(columns) columns: \(targets(rig))")
    }

    @Test(arguments: [44, 50, 52, 56])
    func `in a notice`(columns: Int) {
        let rig = rig([.notice("See \(Self.path):12:5 now.", isError: false)], columns: columns)
        #expect(targets(rig) == ["file://\(Self.path)#L12C5"], "\(columns) columns: \(targets(rig))")
    }

    @Test(arguments: [44, 50, 52, 56])
    func `in a tool's output`(columns: Int) {
        let rig = rig(
            [
                .toolStarted(name: "bash", summary: "build", id: "t", command: ToolCommand()),
                .toolFinished(.failed("1"), output: "error at \(Self.path):12:5: oops", id: "t")
            ],
            columns: columns
        )
        #expect(targets(rig).contains("file://\(Self.path)#L12C5"), "\(columns) columns: \(targets(rig))")
        #expect(
            targets(rig).allSatisfy { $0.hasPrefix("file://\(Self.path)") },
            "no link to part of the path: \(targets(rig))"
        )
    }
}
