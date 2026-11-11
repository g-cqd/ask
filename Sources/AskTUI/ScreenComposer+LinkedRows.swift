internal import Foundation
internal import TerminalKitText

/// Paths and addresses linked across the rows a line was wrapped into (the owner, 2026-11-11): a path cut by the edge was linked as
/// two pieces naming two files that are not there, and its `:12` on the next row was lost.
extension ScreenComposer {
    /// `rows`, each linked, the rows that show one hard line of plain text read as that line: a link that crosses a row's edge is
    /// one link on each row it covers, to the whole path, with its place. A rendered Markdown row brings its own links and is linked
    /// on its own.
    static func linkedRows(_ rows: [Line], home: String?, commands: Set<String>) -> [Line] {
        var result = rows
        var start = 0
        while start < rows.count {
            var end = start + 1
            while end < rows.count, continues(rows[end - 1], with: rows[end]) { end += 1 }
            if end - start == 1 {
                result[start] = linked(rows[start], home: home, commands: commands)
            } else {
                link(&result, start ..< end, home: home, commands: commands)
            }
            start = end
        }
        return result
    }

    /// Whether `next` is the row `row`'s hard line wrapped onto: the same item and line, starting where `row` ends or one past it,
    /// at the space the wrap dropped.
    private static func continues(_ row: Line, with next: Line) -> Bool {
        guard row.segments.isEmpty, next.segments.isEmpty, let one = row.source, let two = next.source,
            one.block == two.block, one.line == two.line, !one.text.isEmpty
        else { return false }
        let end = one.offset + one.text.count
        return two.offset == end || two.offset == end + 1
    }

    /// Links the rows `range`, which show one hard line, read as that line.
    private static func link(_ rows: inout [Line], _ range: Range<Int>, home: String?, commands: Set<String>) {
        let (text, cells) = joined(rows, range)
        if LinkCandidates.mayHoldLink(text) {
            let starts = columnStarts(of: text)
            let found = PathLinks.located(
                PathLinks.links(in: text, home: home ?? NSHomeDirectory(), commands: commands),
                in: text
            )
            for link in found {
                guard let low = starts.firstIndex(of: link.columns.lowerBound),
                    let high = starts.firstIndex(of: link.columns.upperBound), low < high
                else { continue }
                for (row, columns) in pieces(cells[low ..< high]) {
                    var part = link
                    part.columns = columns
                    guard !rows[row].links.contains(where: { $0.columns.overlaps(columns) }) else { continue }
                    rows[row].links.append(part)
                    rows[row].links.sort { $0.columns.lowerBound < $1.columns.lowerBound }
                }
            }
        }
        // A row's own links, from its escapes or code, still get their places.
        for index in range where !rows[index].links.isEmpty {
            rows[index].links = PathLinks.located(rows[index].links, in: rows[index].text)
        }
    }

    /// A drawn character: the row it is on, its column, and its width; the space a wrap dropped has no width.
    private typealias Cell = (row: Int, column: Int, width: Int)

    /// The hard line the rows `range` show, and for each of its characters where it is drawn.
    private static func joined(_ rows: [Line], _ range: Range<Int>) -> (String, [Cell]) {
        var text = ""
        var cells: [Cell] = []
        for index in range {
            guard let source = rows[index].source else { continue }
            if let last = cells.last, rows[index - 1].source.map({ $0.offset + $0.text.count }) != source.offset {
                text.append(" ")
                cells.append((last.row, last.column + last.width, 0))
            }
            var column = source.col
            for character in source.text {
                let width = UnicodeWidth.displayWidth(of: character)
                text.append(character)
                cells.append((index, column, width))
                column += width
            }
        }
        return (text, cells)
    }

    /// The column each character of `text` starts at, and one past the last.
    private static func columnStarts(of text: String) -> [Int] {
        var starts: [Int] = []
        var column = 0
        for character in text {
            starts.append(column)
            column += UnicodeWidth.displayWidth(of: character)
        }
        starts.append(column)
        return starts
    }

    /// The drawn characters `cells`, cut where the row changes: each row and the columns they cover on it.
    private static func pieces(_ cells: ArraySlice<Cell>) -> [(row: Int, columns: Range<Int>)] {
        var result: [(row: Int, columns: Range<Int>)] = []
        for cell in cells where cell.width > 0 {
            if let last = result.last, last.row == cell.row {
                result[result.count - 1].columns = last.columns.lowerBound ..< cell.column + cell.width
            } else {
                result.append((cell.row, cell.column ..< cell.column + cell.width))
            }
        }
        return result
    }
}
