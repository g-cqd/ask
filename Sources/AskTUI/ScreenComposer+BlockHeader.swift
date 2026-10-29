internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// Only row zero reserves the right-hand status. Selection sources describe content, never the status or its gap.
    static func blockHeader(
        _ text: String, metadata: String, block: Int, width: Int, inset: Int, style: Style
    ) -> [Line] {
        let hardLines = TranscriptContent.hardLines(of: text)
        let text = hardLines[0]
        let available = Swift.max(0, width - UnicodeWidth.displayWidth(of: metadata) - headerGap)
        var prefix = ""
        var cells = 0
        for character in text {
            let next = UnicodeWidth.displayWidth(of: String(character))
            guard cells + next <= available else { break }
            prefix.append(character)
            cells += next
        }
        let suffix = String(text.dropFirst(prefix.count))
        let margin = String(repeating: " ", count: inset)
        let status = ColumnSlicer.split(metadata, columns: 0 ..< width).selected
        let gap = String(repeating: " ", count: Swift.max(0, width - cells - UnicodeWidth.displayWidth(of: status)))
        var result = [
            Line(
                text: margin + prefix + gap + status, style: style,
                source: Source(block: block, line: 0, offset: 0, col: inset, text: prefix))
        ]
        if !suffix.isEmpty {
            result += TextWrap.rows(suffix, width: width)
                .map { row in
                    Line(
                        text: margin + row.text, style: style,
                        source: Source(
                            block: block, line: 0, offset: prefix.count + row.offset, col: inset, text: row.text))
                }
        }
        if hardLines.count > 1 {
            // @dl:accept -- continuation rows and tool body rows use the same source coordinates but different header layout
            result += TextWrap.rows(hardLines.dropFirst().joined(separator: "\n"), width: width)
                .map { row in
                    Line(
                        text: margin + row.text, style: style,
                        source: Source(block: block, line: row.line + 1, offset: row.offset, col: inset, text: row.text)
                    )
                }
        }
        return result
    }

    static func blockMetadata(
        status: Transcript.ToolStatus, output: String, progress: BlockProgress?, localizedDurations: Bool = true,
        lineCount: Int? = nil, toolName: String? = nil
    ) -> String {
        var parts: [String] = []
        if let duration = progress?.duration(localized: localizedDurations) { parts.append(duration) }
        let isWriteAck = toolName == "write"
        let count =
            isWriteAck
            ? 0
            : (lineCount ?? (output.isEmpty ? 0 : TranscriptContent.hardLineCount(of: output)))
        if count > 0 {
            parts.append("\(count) \(count == 1 ? "line" : "lines")")
        }
        switch status {
            case .running: parts.append(progress?.indicator ?? "|")
            case .succeeded: parts.append("✓")
            case .failed(let reason):
                // The tool's strict exit marker is not prose; other errors stay in its output, not the status column.
                let code =
                    reason.hasPrefix("[exit ") && reason.hasSuffix("]") ? Int(reason.dropFirst(6).dropLast()) : nil
                parts.append(code.map { "[\($0)] ✗" } ?? "✗")
        }
        return parts.joined(separator: " · ")
    }
}
