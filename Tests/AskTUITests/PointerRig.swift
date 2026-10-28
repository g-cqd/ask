internal import Foundation
internal import Synchronization
internal import TerminalKitCodecs
internal import TerminalKitIO
internal import TerminalKitInput
internal import TerminalKitRender
internal import TerminalKitText
internal import Testing

@testable import AskTUI

/// A controller, the composer that draws it, and the frame the composer handed to the mouse.
struct PointerRig {
    var controller: ScreenController
    var composer: ScreenComposer
    var buffer: ScreenBuffer
    let frames: FrameBox
    var cursor = (row: 0, column: 0)
    var clock = ContinuousClock.now

    init(
        columns: Int = 30, rows: Int = 12, options: ScreenOptions = .legacy, lines: [String] = [],
        updates: [ConversationUpdate] = []
    ) {
        frames = FrameBox()
        controller = ScreenController(label: "m", options: options)
        composer = ScreenComposer(frames: frames)
        buffer = ScreenBuffer(columns: columns, rows: rows)
        for line in lines { controller.handle(.notice(line, isError: false)) }
        for update in updates { controller.handle(update) }
        draw()
    }

    /// Draws the controller's state, as the render thread would, and shows the mouse that frame.
    mutating func draw() {
        cursor = composer.compose(controller.state, into: &buffer)
        controller.frame = frames.load()
    }

    /// One mouse report, at zero-based cells, then a new frame.
    @discardableResult
    mutating func mouse(
        _ button: MouseButton, _ kind: MouseEventKind, row: Int, col: Int, after delay: Duration = .zero
    ) -> [ScreenController.Effect] {
        clock = clock.advanced(by: delay)
        let event = MouseEvent(button: button, row: row + 1, col: col + 1, kind: kind)
        let effects = controller.handle(.mouse(event), pageRows: 10, at: clock)
        draw()
        return effects
    }

    /// One timer step as the driver takes it: the newest frame, then the tick, then a new frame.
    @discardableResult
    mutating func tick() -> Bool {
        controller.frame = frames.load()
        let changed = controller.tick()
        draw()
        return changed
    }

    /// A press, a move and a release: the gesture of a drag.
    @discardableResult
    mutating func drag(from: (row: Int, col: Int), to: (row: Int, col: Int)) -> [ScreenController.Effect] {
        mouse(.left, .press, row: from.row, col: from.col)
        mouse(.left, .drag, row: to.row, col: to.col)
        return mouse(.left, .release, row: to.row, col: to.col)
    }

    /// A press and a release in the same cell.
    @discardableResult
    mutating func click(row: Int, col: Int, after delay: Duration = .seconds(1)) -> [ScreenController.Effect] {
        mouse(.left, .press, row: row, col: col, after: delay)
        return mouse(.left, .release, row: row, col: col)
    }

    /// The columns of a row drawn inverse.
    func inverse(row: Int) -> [Int] {
        (0 ..< buffer.columns).filter { buffer[row, $0].style.inverse }
    }

    /// The visible content before first-line status, for folding and pointer tests. Metadata has separate cell-exact tests.
    func contentText(row: Int) -> String {
        let line = text(row: row)
        guard let gap = line.range(of: "    ") else { return line }
        return String(line[..<gap.lowerBound])
    }

    /// What a row shows, as text, trailing blanks dropped.
    func text(row: Int) -> String {
        var line = String(
            (0 ..< buffer.columns).compactMap { buffer[row, $0].isContinuation ? nil : buffer[row, $0].character })
        while let last = line.last, last.isWhitespace { line.removeLast() }
        return line
    }
}
