internal import Foundation
internal import TerminalKitCodecs
internal import TerminalKitIO
internal import TerminalKitInput
internal import TerminalKitRender
internal import TerminalKitStyle
internal import Testing

@testable import AskTUI

/// The tints are mixed from the terminal's own colours and keep its contrast (roadmap 0108).
@Suite("Tints follow the terminal's colours")
struct TerminalColoursTests {
    /// A terminal that says when it has been written to, so a test can wait for a write made off its own task.
    private final class SignallingConnection: TerminalConnection {
        let inner = MockTerminalConnection()
        let written = DispatchSemaphore(value: 0)

        func read(into buffer: UnsafeMutableRawBufferPointer) throws(TerminalError) -> Int {
            try inner.read(into: buffer)
        }
        func write(_ bytes: [UInt8]) throws(TerminalError) { try writeContiguous(ContiguousArray(bytes)) }
        func writeContiguous(_ bytes: ContiguousArray<UInt8>) throws(TerminalError) {
            try inner.writeContiguous(bytes)
            written.signal()
        }
        func enterRawMode() throws(TerminalError) { try inner.enterRawMode() }
        func restoreMode() throws(TerminalError) { try inner.restoreMode() }
        func getSize() throws(TerminalError) -> TerminalSize { try inner.getSize() }
    }

    /// Real profiles: Apple Terminal's Basic in light and dark mode, Solarized both ways, and a light theme with grey text.
    private static let pages: [(String, TerminalPage)] = [
        ("Terminal Basic light", .init(background: SIMD3(255, 255, 255), foreground: SIMD3(0, 0, 0))),
        ("Terminal Basic dark", .init(background: SIMD3(30, 30, 30), foreground: SIMD3(255, 255, 255))),
        ("Solarized light", .init(background: SIMD3(253, 246, 227), foreground: SIMD3(101, 123, 131))),
        ("Solarized dark", .init(background: SIMD3(0, 43, 54), foreground: SIMD3(131, 148, 150))),
        ("One Light", .init(background: SIMD3(250, 250, 250), foreground: SIMD3(56, 58, 66)))
    ]

    private func channels(_ color: Color) throws -> SIMD3<Double> {
        guard case .rgb(let r, let g, let b) = color else { throw CancellationError() }
        return SIMD3(Double(r), Double(g), Double(b))
    }

    @Test func `text on every tint keeps nearly all of the terminal's own contrast`() throws {
        for (name, page) in Self.pages {
            let theme = ScreenTheme(page: page)
            let own = TerminalPage.contrast(page.foreground, page.background)
            for tint in theme.tints {
                let kept = TerminalPage.contrast(page.foreground, try channels(tint)) / own
                #expect(kept >= 0.8, "\(name): text on \(tint) keeps \(kept) of its contrast")
                #expect(
                    TerminalPage.contrast(try channels(tint), page.background) > 1.04, "\(name): \(tint) is visible"
                )
            }
        }
    }

    @Test func `a light page gets light tints and a dark page dark ones`() throws {
        for tint in ScreenTheme(page: .light).tints {
            #expect(TerminalPage.luminance(try channels(tint)) > 0.7, "\(tint)")
        }
        for tint in ScreenTheme(page: .dark).tints {
            #expect(TerminalPage.luminance(try channels(tint)) < 0.05, "\(tint)")
        }
        #expect(TerminalPage(background: SIMD3(253, 246, 227)).isLight)
        #expect(!TerminalPage(background: SIMD3(0, 43, 54)).isLight)
    }

    @Test func `adopting the terminal's page retints the blocks and the input, keeping tint off off`() {
        var state = ScreenState(label: "m", options: ScreenOptions())
        let before = state.theme.inputBackground
        state.adopt(.light)
        #expect(state.theme.inputBackground != before && state.blocks.theme == state.theme)
        var plain = ScreenState(label: "m", options: ScreenOptions(tint: false))
        plain.adopt(.light)
        #expect(plain.theme.inputBackground == .default)
    }

    @Test func `the colours take their own events, ask off the loop, and follow only on auto`() throws {
        let connection = SignallingConnection()
        var colours = try #require(TerminalColours(following: ScreenOptions(), connection: connection))
        #expect(colours.take(.askColours) == .consumed)
        #expect(connection.written.wait(timeout: .now() + 5) == .success)
        #expect(connection.inner.writtenOutput == PageFollower.query)
        #expect(colours.take(.input(.unknown(Array("\u{1b}]10;rgb:00/00/00\u{07}".utf8)))) == .consumed)
        #expect(colours.take(.input(.unknown(Array("\u{1b}]11;rgb:ff/ff/ff\u{07}".utf8)))) == .page(.light))
        #expect(colours.take(.input(.unknown(Array("\u{1b}[?62;c".utf8)))) == nil)
        #expect(colours.take(.tick) == nil)
        var fixed = ScreenOptions()
        fixed.appearance = .dark
        #expect(TerminalColours(following: fixed, connection: connection) == nil)
        #expect(
            TerminalColours(following: ScreenOptions(tint: false), connection: connection) != nil,
            "secondary text needs the page")
    }

    @Test func `secondary text is never faint, and on a known page it is a grey that stays readable`() throws {
        for (name, page) in Self.pages {
            let theme = ScreenTheme(page: page)
            var drawn = theme.legible(Style(dim: true))
            if drawn.fg == .default {
                drawn.fg = .rgb(r: UInt8(page.foreground.x), g: UInt8(page.foreground.y), b: UInt8(page.foreground.z))
            }
            #expect(!drawn.dim, "\(name)")
            let grey = try channels(drawn.fg)
            let own = TerminalPage.contrast(page.foreground, page.background)
            let readable = TerminalPage.contrast(grey, page.background) >= Swift.min(4.5, own - 0.01)
            #expect(readable, "\(name): secondary \(grey) reads at 4.5:1, or as well as the theme's own text")
            if own >= 7 {
                #expect(grey != page.foreground, "\(name): on a contrasted page, secondary differs from the text")
            }
        }
        let status = ScreenTheme(page: .light).legible(Style(fg: .indexed(2), dim: true))
        #expect(status == Style(fg: .indexed(2)), "coloured text keeps its colour, at full strength")
        #expect(ScreenTheme(page: .light).legible(Style(bold: true)) == Style(bold: true), "other text is untouched")
        let guessed = ScreenTheme(light: true).legible(Style(dim: true))
        #expect(guessed == Style(dim: true), "on a guessed page, faint stays, never a grey that could vanish")
    }

    @Test func `the screen draws no faint cell, and draws output in the page's grey once the page is known`() {
        let updates: [ConversationUpdate] = [
            .toolStarted(name: "shell", summary: "", id: "c", fullInput: "ls", command: ToolCommand()),
            .toolFinished(.succeeded, output: "OUTPUT", id: "c")
        ]
        var options = ScreenOptions(foldTools: false)
        options.appearance = .light
        let rig = PointerRig(columns: 40, rows: 12, options: options, updates: updates)
        let cells = (0 ..< 12).flatMap { row in (0 ..< 40).map { rig.buffer[row, $0].style } }
        #expect(!cells.contains { $0.dim })
        let output = (0 ..< 12).flatMap { row in (0 ..< 40).map { (row, $0) } }
            .first { rig.buffer[$0.0, $0.1].character == "O" && rig.text(row: $0.0).hasSuffix("OUTPUT") }
        let expected = ScreenTheme(page: .light).legible(Style(dim: true)).fg
        #expect(output.map { rig.buffer[$0.0, $0.1].style.fg } == expected)
    }
}
