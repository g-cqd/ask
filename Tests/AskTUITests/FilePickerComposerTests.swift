import TerminalKitCodecs
import TerminalKitInput
import TerminalKitRender
import TerminalKitText
import Testing

@testable import AskTUI

/// How the file picker is drawn: the path alone on a row, the choice bold, and a title that says what the sandbox hid, what was cut,
/// and that the files are still being listed.
@Suite("The file picker shows paths, and says what it left out")
struct FilePickerComposerTests {
    private func screen(_ files: ProjectFiles?, typing text: String, rows: Int = 20) -> ScreenController {
        var controller = ScreenController(label: "m", commands: [], options: .legacy)
        if let files { controller.handle(.files(files)) }
        for scalar in text.unicodeScalars {
            _ = controller.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: rows - 3)
        }
        return controller
    }

    private func rows(_ controller: ScreenController, columns: Int = 70, height: Int = 20) -> [String] {
        var buffer = ScreenBuffer(columns: columns, rows: height)
        var composer = ScreenComposer()
        _ = composer.compose(controller.state, into: &buffer)
        return (0 ..< height)
            .map { row in
                var text = ""
                for column in 0 ..< columns where !buffer[row, column].isContinuation {
                    text.append(buffer[row, column].character)
                }
                while text.hasSuffix(" ") { text.removeLast() }
                return text
            }
    }

    @Test func `a row is the path alone, and the title says how many the sandbox hid`() throws {
        let files = ProjectFiles(paths: ["a/one.txt", "a/two.txt", "b/three.txt"], hidden: 4)
        let shown = rows(screen(files, typing: "@"))
        let title = try #require(shown.firstIndex { $0.hasPrefix("files") })
        #expect(shown[title].contains("4 hidden by the sandbox") && shown[title].contains("Esc closes"))
        #expect(shown[title + 1] == "a/one.txt" && shown[title + 2] == "a/two.txt" && shown[title + 3] == "b/three.txt")
        #expect(shown.dropLast().last == "ask> @")
    }

    @Test func `the choice is bold and a truncated listing says so`() throws {
        let files = ProjectFiles(paths: ["a.txt", "b.txt"], truncated: true)
        var controller = screen(files, typing: "@")
        _ = controller.handle(.key(KeyEvent(keyCode: Key.down.rawValue)), pageRows: 17)
        var buffer = ScreenBuffer(columns: 70, rows: 20)
        var composer = ScreenComposer()
        _ = composer.compose(controller.state, into: &buffer)
        let shown = rows(controller)
        let first = try #require(shown.firstIndex { $0 == "a.txt" })
        #expect(!buffer[first, 0].style.bold && buffer[first + 1, 0].style.bold)
        #expect(shown[first - 1].contains("listing cut at its limit"))
    }

    @Test func `while the files are being listed the picker is one line saying so`() {
        let shown = rows(screen(nil, typing: "@"))
        #expect(shown.filter { $0.hasPrefix("files") } == ["files · looking for files…"])
        #expect(shown.dropLast().last == "ask> @")
    }

    @Test func `matches beyond what fits are counted, and cut matches are named`() throws {
        let many = ProjectFiles(paths: (0 ..< 300).map { "dir/file\($0).txt" })
        let shown = rows(screen(many, typing: "@file"))
        let title = try #require(shown.first { $0.hasPrefix("files") })
        #expect(title.contains("1 of 200") && title.contains("first 200 matches"))
    }

    @Test func `a long path is cut to the width, wide text included`() throws {
        let files = ProjectFiles(paths: [String(repeating: "日本語/", count: 30) + "file.txt"])
        let picker = try #require(screen(files, typing: "@").state.picker)
        for columns in [60, 25, 7, 3, 1] {
            for line in ScreenComposer.pickerLines(picker, columns: columns, rows: 8) {
                #expect(UnicodeWidth.displayWidth(of: line.text) <= columns, "\(line.text) at \(columns)")
            }
        }
    }
}
