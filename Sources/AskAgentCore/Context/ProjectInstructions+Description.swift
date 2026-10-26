extension ProjectInstructions {
    /// One line per instruction file, for the person: what was loaded and what was skipped, and why.
    /// - Parameter files: the files, in the order they were found.
    /// - Returns: their lines, in the same order.
    public static func describe(_ files: [File]) -> [String] {
        files.map { file in
            file.skippedBecause.map { "Skipped \(file.path): \($0)." } ?? "Instructions loaded from \(file.path)."
        }
    }
}
