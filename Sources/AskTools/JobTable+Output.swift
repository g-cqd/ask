internal import Foundation

extension JobTable {
    /// The end of what job `id` has written, for showing a person; nil when the job is unknown or kept no output file.
    /// - Parameters:
    ///   - id: the job's name, such as `job-2`.
    ///   - maximumBytes: how much of the end to read. A cut says so, and starts on a whole line.
    /// - Returns: the text, or nil when there is none to read.
    public func outputTail(of id: String, maximumBytes: Int) -> String? {
        guard let path = job(id)?.outputPath, let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(maximumBytes) ? size - UInt64(maximumBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        guard start > 0 else { return text }
        let whole = text.firstIndex(of: "\n").map { String(text[text.index(after: $0)...]) } ?? text
        return "… earlier output not shown\n" + whole
    }
}
