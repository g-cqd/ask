extension ConfigurationFile {
    /// The `threads` keys (roadmap 0195), each read by its declaration; unknown keys are refused.
    struct ThreadsDecoded: Decodable {
        var section = ThreadsSection()

        init(from decoder: any Decoder) throws {
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                // Retired (note n52): a thread merges only by /merge. Still read, so a file that sets it opens.
                guard key.stringValue != "merge" else {
                    _ = try container.decode(String.self, forKey: key)
                    return
                }
                try section.read(key.stringValue, at: key, in: container)
            }
        }
    }

    /// Counts within range. A project's file may set them too: they only ever limit what runs.
    static func validateThreads(_ section: ThreadsSection?, path: String) throws(ConfigurationError) {
        guard let section else { return }
        if let written = section.questionsAfter, (ThreadsSection.duration(written) ?? nil) == nil {
            throw .outOfRange(
                path: path,
                key: "threads.questionsAfter",
                reason: "takes seconds, minutes or hours, such as \"30s\" or \"2m\""
            )
        }
        if let written = section.mergedShownFor, ThreadsSection.duration(written) == nil {
            throw .outOfRange(
                path: path,
                key: "threads.mergedShownFor",
                reason: "takes minutes, hours or days, such as \"30m\", \"2h\" or \"1d\", or \"always\""
            )
        }
        for (key, value, range) in [
            ("max", section.max, 1 ... ThreadsSection.mostAtOnce),
            ("depth", section.depth, 1 ... ThreadsSection.deepest)
        ] {
            guard let value, !range.contains(value) else { continue }
            throw .outOfRange(
                path: path,
                key: "threads." + key,
                reason: "must be from \(range.lowerBound) to \(range.upperBound)"
            )
        }
    }
}
