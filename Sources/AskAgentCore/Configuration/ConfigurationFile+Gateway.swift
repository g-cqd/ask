extension ConfigurationFile {
    /// The gateway is the person's own (ADR-0170): a project's file may not set it. The address is `host:port`, the key a 32-byte key
    /// in base64, and each folder absolute or under `~/`. The first problem found is the one refused.
    static func validateGateway(_ section: GatewaySection?, path: String, isProject: Bool) throws(ConfigurationError) {
        guard let section else { return }
        let checks: [(failed: Bool, key: String, reason: String)] = [
            (isProject, "gateway", "shares this computer's sessions: only your own config file can choose that"),
            (
                section.address.map { GatewaySection.endpoint($0) == nil } ?? false, "gateway.address",
                "takes host:port, such as \"192.168.1.20:7443\""
            ),
            (
                section.key.map { !GatewaySection.isKey($0) } ?? false, "gateway.key",
                "takes the gateway's public key: 32 bytes in base64"
            ),
            (
                (section.folders ?? []).contains { !($0.hasPrefix("/") || $0.hasPrefix("~/")) }, "gateway.folders",
                "takes absolute paths or paths under ~/"
            )
        ]
        if let problem = checks.first(where: \.failed) {
            throw .outOfRange(path: path, key: problem.key, reason: problem.reason)
        }
    }
}
