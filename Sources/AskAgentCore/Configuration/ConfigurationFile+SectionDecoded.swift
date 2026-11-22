extension ConfigurationFile {
    /// A section whose settings are each declared once (roadmap 0209), read key by key through its table: a key that holds an object
    /// of settings (`ui.fold`) is read key by key within it, a retired key is read and ignored, and any other key is refused.
    struct SectionDecoded<Section: DeclaredSection>: Decodable {
        var section = Section()

        init(from decoder: any Decoder) throws {
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                try Self.read(key.stringValue, at: key, in: container, into: &section)
            }
        }

        private static func read(
            _ name: String,
            at key: Key,
            in container: KeyedDecodingContainer<Key>,
            into section: inout Section
        ) throws {
            if Section.retired.contains(name) {
                _ = try container.decode(String.self, forKey: key)
                return
            }
            let holdsSettings =
                Section.settings.named[name] == nil
                && Section.settings.all.contains { $0.name.hasPrefix(name + ".") }
            guard holdsSettings else { return try section.read(name, at: key, in: container) }
            let inner = try container.nestedContainer(keyedBy: Key.self, forKey: key)
            for innerKey in inner.allKeys {
                try read(name + "." + innerKey.stringValue, at: innerKey, in: inner, into: &section)
            }
        }
    }
}
