import Foundation
import TerminalKitCodecs
import TerminalKitStyle
internal import Testing

@testable import AskTUI

/// An `edit` drawn as the lines it removes and adds (roadmap 0152, phase 3): each removed row on a red tint and each added row on a
/// green one, mixed from the page as the block tints are, its marker in red or green, and its code coloured by the file's language.
@Suite("An edit is drawn as the lines it removes and adds")
struct EditDiffTests {
    private static let diff = "  let a = 1\n- let b = 2\n+ let b = 20"

    private static func transcript(
        _ input: String, name: String = "edit", path: String = "a.swift", highlight: Bool = true
    ) -> Transcript {
        var transcript = Transcript()
        transcript.setHighlight(highlight)
        transcript.startTool(name: name, summary: path, id: "call", fullInput: input, path: path)
        transcript.finishTool(.succeeded, output: "Replaced 1 occurrence in \(path).", id: "call")
        transcript.setToolsFoldedByDefault(false)
        return transcript
    }

    private static func row(
        _ text: String, in transcript: Transcript, style: BlockStyle = BlockStyle(), columns: Int = 60
    ) -> ScreenComposer.Line? {
        ScreenComposer.lines(in: transcript, at: 0, columns: columns, style: style).first { $0.text.contains(text) }
    }

    private static func runs(of line: ScreenComposer.Line) -> [(String, Style)] {
        ScreenComposer.spans(of: line, highlight: nil)
    }

    @Test func `removed and added rows take their own tints whole, and kept rows the block's`() throws {
        let theme = BlockStyle().theme
        let transcript = Self.transcript(Self.diff)
        let removed = try #require(Self.row("- let b = 2", in: transcript))
        let added = try #require(Self.row("+ let b = 20", in: transcript))
        let kept = try #require(Self.row("  let a = 1", in: transcript))
        #expect(removed.style.bg == theme.diffRemoved)
        #expect(added.style.bg == theme.diffAdded)
        #expect(kept.style.bg == theme.success)
        #expect(
            Self.runs(of: removed).allSatisfy { $0.1.bg == theme.diffRemoved },
            "the colours of its code keep the row's tint")
        #expect(Self.runs(of: added).allSatisfy { $0.1.bg == theme.diffAdded })
    }

    @Test func `the markers are red and green, tint and highlighting off too`() throws {
        for (style, highlight) in [(BlockStyle(), true), (BlockStyle.plain, false)] {
            let transcript = Self.transcript(Self.diff, highlight: highlight)
            let removed = try #require(Self.row("- let b = 2", in: transcript, style: style))
            let added = try #require(Self.row("+ let b = 20", in: transcript, style: style))
            #expect(Self.runs(of: removed).first { $0.0.hasPrefix("-") }?.1.fg == .indexed(1))
            #expect(Self.runs(of: added).first { $0.0.hasPrefix("+") }?.1.fg == .indexed(2))
            #expect(style.theme.tinted || (removed.style.bg == .default && added.style.bg == .default))
        }
    }

    @Test func `the code is lexed after its marker, so what only counts at the start of a line still does`() throws {
        // A TOML table header is one only at the start of its line.
        let transcript = Self.transcript(
            "- [package]\n+ [workspace]\n  [dependencies]\n  name = \"a\"", path: "Cargo.toml")
        for header in ["[package]", "[workspace]", "[dependencies]"] {
            let row = try #require(Self.row(header, in: transcript))
            #expect(Self.runs(of: row).contains { $0.0.contains(header) && $0.1.fg != .default }, "\(header)")
        }
    }

    @Test func `a kept line carries each side on, so the old text's comment still closes on its own side`() throws {
        // The old text opens a comment, keeps a line, and closes it on its next removed line; the new text has no comment.
        let transcript = Self.transcript("- let a = 1 /* open\n  kept\n- end */ let b = 2\n+ let a = 1")
        let closing = try #require(Self.row("- end */", in: transcript))
        #expect(Self.runs(of: closing).contains { $0.0.contains("end") && $0.1.italic }, "still the old side's comment")
        let keyword = Self.runs(of: closing).last { $0.0.trimmingCharacters(in: .whitespaces) == "let" }
        #expect(keyword?.1.fg == .indexed(5) && keyword?.1.italic == false)
    }

    @Test func `the code after a marker is coloured, the removed and the added lines each lexed on their own`() throws {
        // Lexed as one text, the added line would be inside the comment the removed one opens.
        let transcript = Self.transcript("- let s = 1 /* note\n+ let s = 2\n  done()")
        let added = try #require(Self.row("+ let s = 2", in: transcript))
        let keyword = try #require(Self.runs(of: added).first { $0.0.trimmingCharacters(in: .whitespaces) == "let" })
        #expect(keyword.1.fg == .indexed(5) && !keyword.1.italic)
        let removed = try #require(Self.row("- let s = 1", in: transcript))
        #expect(Self.runs(of: removed).contains { $0.0.contains("note") && $0.1.italic })
        #expect(Self.runs(of: removed).first { $0.0.hasPrefix("-") }?.1.italic == false, "the marker is no code")
    }

    @Test func `wrapping a diff row never changes the style of any of its characters`() {
        let input = "  \tlet 漢字 = \"é, 🇫🇷\" // 終わり\n- let x = f(0x1F) + \"long text\" // gone\n+ let x = g(0b1) // new 🙂"
        let transcript = Self.transcript(input)
        let reference = Self.characterStyles(transcript, columns: 400)
        for columns in 3 ... 60 {
            for (place, style) in Self.characterStyles(transcript, columns: columns) {
                #expect(reference[place] == style, "\(columns) columns, line \(place.line), grapheme \(place.offset)")
            }
        }
    }

    @Test func `other tools' lines that start like a marker are not diff rows`() throws {
        let theme = BlockStyle().theme
        for name in ["write", "shell"] {
            let transcript = Self.transcript("- item\n+ other", name: name, path: "notes.md")
            #expect(try #require(Self.row("- item", in: transcript)).style.bg == theme.success)
        }
    }

    @Test func `the diff tints stand apart from the block tints they sit among`() {
        for page in [TerminalPage.light, .dark] {
            let theme = ScreenTheme(page: page)
            let tints: [Color] = [theme.diffAdded, theme.diffRemoved, theme.success, theme.failure]
            #expect(Set(tints).count == 4)
            #expect(theme.tints.contains(theme.diffAdded) && theme.tints.contains(theme.diffRemoved))
        }
    }

    /// The style each grapheme of the edit's input is drawn in, by its hard line and grapheme offset in that line.
    private static func characterStyles(_ transcript: Transcript, columns: Int) -> [Place: Style] {
        var result: [Place: Style] = [:]
        for line in ScreenComposer.lines(in: transcript, at: 0, columns: columns, style: BlockStyle()) {
            guard let source = line.source, (1 ... 3).contains(source.line) else { continue }
            var offset = source.offset
            var skipped = 0
            for (text, style) in ScreenComposer.spans(of: line, highlight: nil) {
                for _ in text {
                    // The block's inset column comes before the row's own text.
                    if skipped < source.col {
                        skipped += 1
                        continue
                    }
                    guard offset < source.offset + source.text.count else { break }
                    result[Place(line: source.line, offset: offset)] = style
                    offset += 1
                }
            }
        }
        return result
    }

    struct Place: Hashable {
        var line: Int
        var offset: Int
    }
}
