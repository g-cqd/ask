extension ConfigurationFile {
    /// The `threads` keys (roadmap 0195); unknown keys are refused.
    struct ThreadsDecoded: Decodable {
        var section = ThreadsSection()

        init(from decoder: any Decoder) throws {
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                // @dl:accept -- a key table decoded by the shared walk, as every section's is; the keys are the data
                switch key.stringValue {
                    case "max": section.max = try container.decode(Int.self, forKey: key)
                    // @dl:accept -- key table rows
                    case "depth": section.depth = try container.decode(Int.self, forKey: key)
                    case "names": section.names = try ConfigurationFile.choice(container, key, "threads.names")
                    case "mergedShownFor": section.mergedShownFor = try container.decode(String.self, forKey: key)
                    case "namesModel": section.namesModel = try container.decode(String.self, forKey: key)
                    case "model": section.model = try container.decode(String.self, forKey: key)
                    case "merge": section.merge = try ConfigurationFile.choice(container, key, "threads.merge")
                    case "summaryInstructions":
                        section.summaryInstructions = try container.decode(String.self, forKey: key)
                    case "questions":
                        section.questions = try ConfigurationFile.word(
                            container,
                            key,
                            "threads.questions",
                            ThreadsSection.questionWords
                        )
                    case "questionsAfter": section.questionsAfter = try container.decode(String.self, forKey: key)
                    default: throw UnknownKey(key: "threads." + key.stringValue)
                }
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
