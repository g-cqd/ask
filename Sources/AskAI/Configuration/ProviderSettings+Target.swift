public import Foundation

extension ProviderSettings {
    /// A configured provider or preset before a model is chosen: its entry, its preset and the protocol and address it speaks.
    struct Target {
        let name: String
        let entry: Entry
        let preset: ProviderPreset?
        let api: String
        let baseURL: String
    }

    /// Where a provider's requests go, for a request that names no model: its list.
    public struct Listing: Sendable, Equatable {
        public let name: String
        public let baseURL: URL
        public let apiKey: String?
        public let headers: [String: String]

        /// The address, key and headers of provider `name`.
        public init(name: String, baseURL: URL, apiKey: String?, headers: [String: String]) {
            self.name = name
            self.baseURL = baseURL
            self.apiKey = apiKey
            self.headers = headers
        }
    }

    /// The provider's address, key and headers, for reading its model list.
    /// - Parameters:
    ///   - provider: the name given on the command line, if any; else the file's default.
    ///   - environment: where `$NAME` keys and a preset's key variable are read.
    ///   - storedKeys: the keys sign-ins stored, called only when nothing else gives a preset a key.
    /// - Returns: nil for a built-in provider (Anthropic and Codex have their own sign-in and catalogs).
    /// - Throws: a ``ProviderSettingsError`` naming what cannot be honoured. A preset with no key is an error, as it is for a
    ///   run: the list is never asked for without the key the provider's requests would carry.
    public func listing(
        provider: String?, environment: [String: String],
        storedKeys: () throws(CredentialFileError) -> [String: String] = { [:] }
    ) throws(ProviderSettingsError) -> Listing? {
        let name = selectedProvider(provider)
        if [Self.anthropic, Self.codex].contains(name) { return nil }
        let target = try target(name, environment: environment, storedKeys: storedKeys)
        let (url, key) = try endpoint(of: target, environment: environment, storedKeys: storedKeys)
        return Listing(name: name, baseURL: url, apiKey: key, headers: target.entry.headers ?? [:])
    }

    /// The configured provider or preset called `name`.
    /// - Throws: ``ProviderSettingsError/unknownProvider(_:known:)``, ``ProviderSettingsError/incomplete(provider:field:)``
    ///   or ``ProviderSettingsError/unsupportedAPI(provider:api:)``.
    func target(
        _ name: String, environment: [String: String], storedKeys: () throws(CredentialFileError) -> [String: String]
    ) throws(ProviderSettingsError) -> Target {
        let preset = ProviderPreset.named(name)
        guard let entry = entries[name] ?? (preset != nil ? Entry() : nil) else {
            throw .unknownProvider(name, known: known(environment: environment, stored: (try? storedKeys()) ?? [:]))
        }
        let api = entry.api ?? (preset != nil ? Self.openAICompletions : nil)
        guard let api else { throw .incomplete(provider: name, field: "api") }
        guard api == Self.openAICompletions || api == Self.openAIResponses else {
            throw .unsupportedAPI(provider: name, api: api)
        }
        guard let baseURL = entry.baseUrl ?? preset?.address(environment: environment) else {
            throw .incomplete(provider: name, field: "baseUrl")
        }
        return Target(name: name, entry: entry, preset: preset, api: api, baseURL: baseURL)
    }

    /// The address and the key to send, after the endpoint policy has agreed the key may go there.
    /// - Throws: a key problem from ``credential(of:entry:preset:environment:stored:)`` or
    ///   ``ProviderSettingsError/refusedEndpoint(provider:reason:)``.
    func endpoint(
        of target: Target, environment: [String: String],
        storedKeys: () throws(CredentialFileError) -> [String: String]
    ) throws(ProviderSettingsError) -> (url: URL, key: String?) {
        let key = try credential(
            of: target.name, entry: target.entry, preset: target.preset, environment: environment, stored: storedKeys)
        let trimmed = target.baseURL.hasSuffix("/") ? String(target.baseURL.dropLast()) : target.baseURL
        guard let url = URL(string: trimmed) else {
            throw .refusedEndpoint(provider: target.name, reason: "it is not a URL")
        }
        if let reason = EndpointPolicy.refusal(for: url, carriesCredential: key != nil) {
            throw .refusedEndpoint(provider: target.name, reason: reason)
        }
        return (url, key)
    }
}
