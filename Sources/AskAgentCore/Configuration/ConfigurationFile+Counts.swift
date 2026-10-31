extension ConfigurationFile {
    /// The settings that count something, each refused below its least useful value.
    static func validateCounts(_ file: ConfigurationFile, path: String) throws(ConfigurationError) {
        let counts: [(key: String, count: Int?, least: Int)] = [
            ("ui.scrollLines", file.ui?.scrollLines, 1), ("ui.inputRows", file.ui?.promptRows, 1),
            ("ui.fold.codeLines", file.ui?.codeFoldLines, 1),
            // Each end of a folded output keeps half, so a line or 32 bytes at the least.
            ("ui.fold.outputLines", file.ui?.outputFoldLines, 2), ("ui.fold.outputBytes", file.ui?.outputFoldBytes, 64),
            ("maxTurns", file.maxTurns, 1)
        ]
        for (key, count, least) in counts {
            if let count, count < least {
                throw .outOfRange(path: path, key: key, reason: "must be at least \(least)")
            }
        }
    }
}
