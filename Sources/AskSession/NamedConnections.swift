package import AskAI
internal import Foundation

/// Binds named registrations to ask's private config directory, never to a project-supplied credential path.
package enum NamedConnections {
    package static func registry(environment: [String: String] = LaunchEnvironment.values) -> ConnectionRegistry {
        ConnectionRegistry(
            directory: CredentialFile.standard(environment: environment).url.deletingLastPathComponent()
                .appending(path: "connections")
        )
    }

    static func file(
        for connection: ConnectionRecord?,
        environment: [String: String] = LaunchEnvironment.values
    ) -> CredentialFile {
        connection.map { registry(environment: environment).credentials(for: $0) }
            ?? .standard(environment: environment)
    }

    package static func aliases(
        for record: ConnectionRecord,
        environment: [String: String] = LaunchEnvironment.values
    ) -> ModelAliasFile {
        registry(environment: environment).aliases(for: record)
    }

    package static func reserved() throws -> [String] {
        try ProviderSettings.load(from: askConfigDirectory() + "/providers.json").configuredNames
    }

    package static func named(_ raw: String, environment: [String: String] = LaunchEnvironment.values) throws
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

    package static func report(_ notices: [String]) {
        for notice in notices { FileHandle.standardError.write(Data(("ask: " + notice + "\n").utf8)) }
    }
}
