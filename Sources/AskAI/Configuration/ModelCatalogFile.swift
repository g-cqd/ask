internal import AemiJSON
internal import Darwin
public import Foundation

/// A replaceable, credential-free model catalog. Reads never repair or rewrite it.
public struct ModelCatalogFile: Sendable {
    public let url: URL
    /// The file to use; its parent directory is created only on a save.
    public init(url: URL) { self.url = url }

    /// A fresh catalog for exactly `scope`, or nil when absent, expired or belonging to another scope.
    /// - Parameters:
    ///   - scope: the account and endpoint the caller will use.
    ///   - now: wall time in seconds since 1970.
    /// - Returns: models no more than one day old, without reading credentials or using a network.
    /// - Throws: ``ModelCatalogError/cache(path:)`` for unreadable or malformed data.
    public func load(scope: ModelCatalogScope, now: Double) throws -> [CatalogModel]? {
        do {
            guard let bytes = try contents() else { return nil }
            let cached = try AemiJSON.JSONDecoder().decode(Stored.self, from: bytes)
            guard cached.version == 1, cached.fetchedAt.isFinite, Self.valid(cached.models) else {
                throw ModelCatalogError.cache(path: url.path)
            }
            guard cached.scope == scope, now.isFinite, now >= cached.fetchedAt,
                now - cached.fetchedAt < 86_400
            else { return nil }
            return cached.models
        } catch { throw ModelCatalogError.cache(path: url.path) }
    }

    /// One model of a fresh catalog for exactly `scope`, reading only what that needs.
    ///
    /// A catalog can list hundreds of models and a run needs one: this finds it without decoding and checking the rest.
    /// Only the header and the one entry are checked, so a damaged entry elsewhere costs nothing here;
    /// ``load(scope:now:)`` is what reports it.
    /// - Parameters:
    ///   - id: the model's id, exactly as the server lists it.
    ///   - scope: the account and endpoint the caller will use.
    ///   - now: wall time in seconds since 1970.
    /// - Returns: nil when the file is absent, expired, another scope's, or does not list `id`.
    /// - Throws: ``ModelCatalogError/cache(path:)`` for a file that cannot be read, a header that is not one, or the one entry
    ///   being damaged.
    public func model(_ id: String, scope: ModelCatalogScope, now: Double) throws -> CatalogModel? {
        do {
            guard let bytes = try contents() else { return nil }
            // One parse: the header and the entry are both read from the same tape.
            let document = try AemiJSON.parse(bytes)
            let header = try AemiJSON.JSONDecoder().decode(Header.self, from: document)
            guard header.version == 1, header.fetchedAt.isFinite else { throw ModelCatalogError.cache(path: url.path) }
            guard header.scope == scope, now.isFinite, now >= header.fetchedAt, now - header.fetchedAt < 86_400
            else { return nil }
            let models = document.root["models"]
            guard models.isArray else { throw ModelCatalogError.cache(path: url.path) }
            var found: JSON?
            models.forEachElement { entry in
                if found == nil, entry["id"].string == id { found = entry }
            }
            guard let found else { return nil }
            let model = try AemiJSON.JSONDecoder().decode(CatalogModel.self, from: found)
            guard model.isValid else { throw ModelCatalogError.cache(path: url.path) }
            return model
        } catch { throw ModelCatalogError.cache(path: url.path) }
    }

    /// Saves an entire catalog atomically; this explicit write may replace an obsolete or damaged cache.
    /// - Parameters:
    ///   - models: nonempty, unique model descriptors with validated ids and positive limits.
    ///   - scope: the account and endpoint that supplied the models.
    ///   - now: wall time in seconds since 1970.
    /// - Throws: ``ModelCatalogError/cache(path:)`` when validation or the save fails.
    public func save(_ models: [CatalogModel], scope: ModelCatalogScope, now: Double) throws {
        guard now.isFinite, Self.valid(models) else { throw ModelCatalogError.cache(path: url.path) }
        let bytes: [UInt8]
        do {
            bytes = try AemiJSON.JSONEncoder()
                .encodeToBytes(Stored(version: 1, scope: scope, fetchedAt: now, models: models))
            guard bytes.count <= Self.byteLimit else { throw ModelCatalogError.cache(path: url.path) }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try AtomicFile.replace(url, with: bytes)
        } catch { throw ModelCatalogError.cache(path: url.path) }
    }

    private static let byteLimit = 2 << 20

    /// The file's bytes, or nil when there is none.
    /// - Throws: ``ModelCatalogError/cache(path:)`` when it is not a regular file of a believable size.
    private func contents() throws -> [UInt8]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
            let size = attributes[.size] as? NSNumber, size.intValue <= Self.byteLimit
        else {
            throw ModelCatalogError.cache(path: url.path)
        }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= Self.byteLimit else { throw ModelCatalogError.cache(path: url.path) }
        return Array(bytes)
    }

    /// What a freshness check needs: not the models.
    private struct Header: Decodable {
        let version: Int
        let scope: ModelCatalogScope
        let fetchedAt: Double
    }

    private static func valid(_ models: [CatalogModel]) -> Bool {
        !models.isEmpty && models.allSatisfy(\.isValid) && Set(models.map(\.id)).count == models.count
    }

    private struct Stored: Codable {
        let version: Int
        let scope: ModelCatalogScope
        let fetchedAt: Double
        let models: [CatalogModel]
    }
}
