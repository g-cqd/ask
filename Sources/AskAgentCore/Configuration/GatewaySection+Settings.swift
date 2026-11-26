// The gateway settings (ADR-0170), each declared once (roadmap 0209).
// @dl:disable near-clone -- a section's settings are data: a key, its field, a type, an example, a default and help each
// @dl:disable structural-clone -- the same rows, matched by their shape
extension GatewaySection: DeclaredSection {
    static let settings = SettingTable<GatewaySection>(
        "gateway",
        [
            .bool(
                SettingCatalog.row(
                    "gateway.enabled",
                    .boolean,
                    "true",
                    "false",
                    user: true,
                    "Whether this computer offers its sessions to the gateway: every session, while on."
                ),
                \.enabled
            ),
            .string(
                SettingCatalog.row(
                    "gateway.address",
                    .text,
                    #""192.168.1.20:7443""#,
                    "none",
                    user: true,
                    "The gateway on the local network, as host:port."
                ),
                \.address
            ),
            .string(
                SettingCatalog.row(
                    "gateway.key",
                    .text,
                    #""AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=""#,
                    "none",
                    user: true,
                    "The gateway's public key, base64; a gateway holding another key is refused."
                ),
                \.key
            ),
            .list(
                SettingCatalog.row(
                    "gateway.folders",
                    .structured,
                    #"["~/Developer"]"#,
                    "none",
                    user: true,
                    "The folders a controller may start a session in, absolute or under ~/; none allows none."
                ),
                \.folders
            )
        ]
    )
}
// @dl:enable near-clone
// @dl:enable structural-clone
