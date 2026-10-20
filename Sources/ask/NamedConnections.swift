internal import AskAI
internal import Foundation

/// Binds named registrations to ask's private config directory, never to a project-supplied credential path.
enum NamedConnections {
    static func registry(environment: [String: String] = ProcessInfo.processInfo.environment) -> ConnectionRegistry {
        ConnectionRegistry(
            directory: CredentialFile.standard(environment: environment).url.deletingLastPathComponent()
                .appending(path: "connections"))
    }

    static func file(
        for connection: ConnectionRecord?, environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CredentialFile {
        connection.map { registry(environment: environment).credentials(for: $0) }
            ?? .standard(environment: environment)
    }

    static func aliases(
        for record: ConnectionRecord, environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ModelAliasFile {
        registry(environment: environment).aliases(for: record)
    }

    static func reserved() throws -> [String] {
        try ProviderSettings.load(from: askConfigDirectory() + "/providers.json").configuredNames
    }

    static func named(_ raw: String, environment: [String: String] = ProcessInfo.processInfo.environment) throws
        -> ConnectionRecord
    {
        guard let name = ConnectionRecord.canonical(raw) else { throw ConnectionError.invalidName }
        let listing = try registry(environment: environment).list()
        report(listing.notices)
        guard let record = listing.records.first(where: { $0.name == name }) else {
            throw ConnectionError.notFound(name)
        }
        return record
    }

    static func report(_ notices: [String]) {
        for notice in notices { FileHandle.standardError.write(Data(("ask: " + notice + "\n").utf8)) }
    }
}
