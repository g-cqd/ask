extension ConfigurationFile {
    /// The `jobs` keys (t232); unknown keys are refused.
    // @dl:accept -- each section decodes its own keys through the shared walk; the tables are the data
    struct JobsDecoded: Decodable {
        var section = JobsSection()
        init(from decoder: any Decoder) throws {
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                switch key.stringValue {
                    case "keepFinished":
                        section.keepFinished = try decodeCount(
                            container,
                            key: key,
                            named: "jobs.keepFinished",
                            least: 0
                        )
                    default: throw UnknownKey(key: "jobs." + key.stringValue)
                }
            }
        }
    }
}
