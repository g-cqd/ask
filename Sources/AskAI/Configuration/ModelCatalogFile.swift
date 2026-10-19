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
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                let size = attributes[.size] as? NSNumber, size.intValue <= Self.byteLimit
            else {
                throw ModelCatalogError.cache(path: url.path)
            }
            let bytes = try Data(contentsOf: url)
            guard bytes.count <= Self.byteLimit else { throw ModelCatalogError.cache(path: url.path) }
            let cached = try AemiJSON.JSONDecoder().decode(Stored.self, from: Array(bytes))
            guard cached.version == 1, cached.fetchedAt.isFinite, Self.valid(cached.models) else {
                throw ModelCatalogError.cache(path: url.path)
            }
            guard cached.scope == scope, now.isFinite, now >= cached.fetchedAt,
                now - cached.fetchedAt < 86_400
            else { return nil }
            return cached.models
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
        let directory = url.deletingLastPathComponent()
        do {
            bytes = try AemiJSON.JSONEncoder()
                .encodeToBytes(Stored(version: 1, scope: scope, fetchedAt: now, models: models))
            guard bytes.count <= Self.byteLimit else { throw ModelCatalogError.cache(path: url.path) }
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // @dl:accept -- the POSIX atomic-file dance matches credential storage, but a replaceable catalog has distinct validation and failure semantics
        } catch { throw ModelCatalogError.cache(path: url.path) }
        let temporary = directory.appending(path: ".models-\(UUID().uuidString).json")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw ModelCatalogError.cache(path: url.path) }
        // @dl:accept -- secure create/write/rename is the same BSD API sequence; do not couple disposable cache writes to credential transactions
        defer { unlink(temporary.path) }
        // The buffer belongs to bytes and remains alive for this synchronous write.
        let written = bytes.withUnsafeBytes { unsafe Darwin.write(descriptor, $0.baseAddress, $0.count) }
        let flushed = fsync(descriptor)
        close(descriptor)
        guard written == bytes.count, flushed == 0, rename(temporary.path, url.path) == 0 else {
            throw ModelCatalogError.cache(path: url.path)
        }
    }

    private static let byteLimit = 2 << 20

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
