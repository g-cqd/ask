internal import AskAI
internal import AskAgentCore
internal import Foundation

/// Maps stable session identities to current local labels without exposing credentials in the session log.
enum SessionRouting {
    static func destination(_ model: ResolvedModel) -> SessionDestination {
        if let connection = model.connection {
            return SessionDestination(
                connectionID: "named:" + connection.id.uuidString.lowercased(),
                authorizationID: connection.authorizationID.uuidString.lowercased(),
                name: connection.name, model: model.model)
        }
        let name: String
        switch model.provider {
            case .anthropic: name = ProviderSettings.anthropic
            case .codex: name = ProviderSettings.codex
            case .openAICompatible(let value, _, _, _), .openAIResponses(let value, _, _, _): name = value
        }
        return SessionDestination(
            connectionID: SessionDestination.providerPrefix + name, authorizationID: nil, name: name, model: model.model
        )
    }

    static func pinnedProvider(_ destination: SessionDestination, environment: [String: String]) throws -> String {
        if destination.connectionID.hasPrefix("named:"),
            let id = UUID(uuidString: String(destination.connectionID.dropFirst(6)))
        {
            let listing = try NamedConnections.registry(environment: environment).list()
            NamedConnections.report(listing.notices)
            guard let record = listing.records.first(where: { $0.id == id }),
                record.authorizationID.uuidString.lowercased() == destination.authorizationID
            else {
                throw SessionDestinationError.changed
            }
            return record.name
        }
        guard destination.connectionID == SessionDestination.providerPrefix + destination.name else {
            throw SessionDestinationError.changed
        }
        return destination.name
    }
}
