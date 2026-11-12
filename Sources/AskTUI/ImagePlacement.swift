internal import TerminalKitCodecs

/// A picture placed in the terminal as pixels (roadmap 0208): sent once under its id, then placed virtually, so the placeholder cells
/// the screen draws under its line show it, and it moves with the text.
struct ImagePlacement: Sendable, Equatable {
    /// The id the terminal knows it by, which the placeholder cells' colour names.
    let id: UInt32
    let columns: Int
    let rows: Int

    /// The cells a picture of `pixels` takes, for cells of `cell` pixels: never more than its own pixels need, nor `maxColumns` or
    /// `maxRows`, and its shape kept (the side the cap cuts decides the other, rounded up so it is not cut short); at least one.
    static func fit(pixels: (width: Int, height: Int), cell: (width: Int, height: Int), maxColumns: Int, maxRows: Int)
        -> (columns: Int, rows: Int)
    {
        let (width, height) = (max(1, pixels.width), max(1, pixels.height))
        let (cellWidth, cellHeight) = (max(1, cell.width), max(1, cell.height))
        var columns = min(max(1, maxColumns), ceilDivide(width, cellWidth))
        var rows = max(1, ceilDivide(columns * cellWidth * height, width * cellHeight))
        if rows > max(1, maxRows) {
            rows = max(1, maxRows)
            columns = max(1, ceilDivide(rows * cellHeight * width, height * cellWidth))
        }
        return (columns, rows)
    }

    private static func ceilDivide(_ value: Int, _ divisor: Int) -> Int { (value + divisor - 1) / divisor }

    /// The command that places `id`, already sent, again over `columns` by `rows` cells: its placement replaced, the picture kept.
    static func placement(id: UInt32, columns: Int, rows: Int) -> [UInt8] {
        var placement = GraphicsCommand.Placement(id: 1, columns: UInt32(max(1, columns)), rows: UInt32(max(1, rows)))
        placement.isVirtual = true
        return GraphicsEncoder.encode(GraphicsCommand(action: .placement, id: id, placement: placement, isQuiet: true))
    }

    /// The commands that send `png` under `id` and place it virtually over `columns` by `rows` cells, both quiet (`q=2`), so no
    /// answer lands in the input.
    static func commands(id: UInt32, png: [UInt8], columns: Int, rows: Int) -> [UInt8] {
        let transmit = GraphicsCommand(
            action: .transmit,
            format: .png,
            transmission: .direct,
            id: id,
            payload: png,
            isQuiet: true
        )
        return GraphicsEncoder.encode(transmit) + placement(id: id, columns: columns, rows: rows)
    }

    /// The command that deletes `id` from the terminal and frees its data, quietly.
    static func deletion(id: UInt32) -> [UInt8] {
        GraphicsEncoder.encode(
            GraphicsCommand(action: .delete, deletion: .image(id: id, freeingData: true), isQuiet: true)
        )
    }
}
