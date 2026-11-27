internal import Foundation

/// Generates a `launchd` user-agent property list (`~/Library/LaunchAgents/studio.aemi.ask.gateway.<role>.plist`) for running either
/// `ask gateway node` on a computer with sessions or `ask gateway serve` on the gateway's computer (ADR-0170).
package enum GatewayLaunchdPlist {
    package static func render(label: String, arguments: [String], logDirectory: String) -> String {
        let items = arguments.map { "        <string>\(escape($0))</string>" }.joined(separator: "\n")
        let outLog = escape(logDirectory + "/\(label).out.log")
        let errLog = escape(logDirectory + "/\(label).err.log")
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>\(escape(label))</string>
                <key>ProgramArguments</key>
                <array>
            \(items)
                </array>
                <key>KeepAlive</key>
                <true/>
                <key>RunAtLoad</key>
                <true/>
                <key>ThrottleInterval</key>
                <integer>5</integer>
                <key>StandardOutPath</key>
                <string>\(outLog)</string>
                <key>StandardErrorPath</key>
                <string>\(errLog)</string>
            </dict>
            </plist>
            """ + "\n"
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
