import Foundation
internal import TerminalKitCodecs
internal import TerminalKitInput
import Testing

@testable import AskTUI

/// Pictures pasted into the input (roadmap 0224; the owner, 2026-11-12): a `[image N]` token where it was pasted, deleted whole by
/// one Backspace, its caption above the input, and the pictures a message still names sent with it and shown in its block.
@Suite("A pasted picture is a token in the draft, a caption above it, and goes with the message")
struct PastedPictureTests {
    private static let png = ToolImage(mediaType: "image/png", data: ToolImageTests.png(1280, 800))
    private static let jpeg = ToolImage(
        mediaType: "image/jpeg",
        data: [0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: 0, count: 60)
    )

    @Test func `tokens are numbered from 1, and a draft names only the pictures whose tokens it still holds, in order`()
    {
        var pictures = PastedPictures()
        #expect(pictures.add(Self.png) == 1 && pictures.add(Self.jpeg) == 2)
        #expect(PastedPictures.token(2) == "[image 2]")
        #expect(pictures.images(in: "see [image 2] then [image 1]") == [Self.jpeg, Self.png])
        #expect(pictures.images(in: "only [image 1], and [image 9] is none") == [Self.png])
        #expect(pictures.images(in: "no pictures here").isEmpty)
        #expect(pictures.attached(in: "[image 2]").map(\.number) == [2])
    }

    @Test func `one Backspace right after a token deletes it whole, and anywhere else one character`() {
        var editor = PromptEditor()
        editor.paste("look [image 1]")
        _ = editor.apply(KeyEvent(keyCode: Key.backspace.rawValue))
        #expect(editor.text == "look " && editor.cursor == 5)
        _ = editor.apply(KeyEvent(keyCode: Key.backspace.rawValue))
        #expect(editor.text == "look")
        editor.paste(" [image 12]!")
        _ = editor.apply(KeyEvent(keyCode: Key.backspace.rawValue))
        #expect(editor.text == "look [image 12]", "the ! goes, not the token")
    }

    @Test func `a pasted path is a picture when it names an image file, quoted, escaped or not`() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ask-pasted-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let plain = folder.appending(path: "shot.png").path
        let spaced = folder.appending(path: "my shot.JPG").path
        let text = folder.appending(path: "notes.txt").path
        for path in [plain, spaced, text] { FileManager.default.createFile(atPath: path, contents: Data([1])) }
        #expect(PastedPath.picture(plain) == plain)
        #expect(PastedPath.picture("  \(plain)\n") == plain, "the blank a terminal adds around a dropped file")
        #expect(PastedPath.picture("'\(spaced)'") == spaced)
        #expect(PastedPath.picture(spaced.replacingOccurrences(of: " ", with: "\\ ")) == spaced)
        #expect(PastedPath.picture(text) == nil, "not a picture's name")
        #expect(PastedPath.picture(folder.appending(path: "gone.png").path) == nil, "no such file")
        #expect(PastedPath.picture(folder.path) == nil)
        #expect(PastedPath.picture("\(plain)\n\(plain)") == nil, "two lines are text")
        #expect(PastedPath.picture("look at shot.png") == nil)
    }

    @Test func `an attached picture is a token at the cursor and a caption above the input; the message shows it`() {
        var controller = ScreenController(label: "m", options: .legacy)
        controller.state.editor.paste("look ")
        _ = controller.handle(.pictureAttached(Self.png))
        #expect(controller.state.editor.text == "look [image 1]")
        let captions = ScreenComposer.pickerLines(for: controller.state, columns: 80, rows: 5).map(\.text)
        #expect(captions.contains { $0.contains("[image 1]") && $0.contains("PNG · 1280×800") }, "\(captions)")
        let effects = controller.handle(.key(KeyEvent(keyCode: Key.enter.rawValue)), pageRows: 30)
        #expect(effects.contains(.startRun("look [image 1]")), "\(effects)")
        let index = controller.state.transcript.items.lastIndex { if case .user = $0 { true } else { false } }
        #expect(index.flatMap { controller.state.transcript.toolImages[$0] } == [Self.png])
        #expect(
            ScreenComposer.pickerLines(for: controller.state, columns: 80, rows: 5).isEmpty,
            "sent: no captions left"
        )
    }

    @Test func `the person's message shows its pictures' captions under its text`() {
        // Drawn as Markdown, as the screen draws a message, and as plain text.
        for markdown in [true, false] {
            var transcript = Transcript()
            transcript.markdown = markdown
            transcript.addUser("look [image 1]")
            transcript.toolImages[0] = [Self.png]
            let rows = ScreenComposer.lines(in: transcript, at: 0, columns: 80)
                .map { $0.text.trimmingCharacters(in: .whitespaces) }
            let message = rows.firstIndex { $0.contains("look [image 1]") }
            let caption = rows.firstIndex { $0.hasPrefix("PNG · 1280×800") }
            #expect(message != nil && caption != nil && message! < caption!, "markdown \(markdown): \(rows)")
        }
    }

    @Test func `a resumed message's pictures show under it`() {
        var controller = ScreenController(label: "m", options: .legacy)
        _ = controller.handle(.userPrompt("look [image 1]"))
        _ = controller.handle(.promptPictures([Self.png]))
        let index = controller.state.transcript.items.count - 1
        #expect(controller.state.transcript.toolImages[index] == [Self.png])
    }
}
