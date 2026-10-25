internal import Foundation

extension AnthropicStreamDecoder {
    /// Interprets explicit HTTP 429 quota refusals before the generic error body. Utilization alone does not establish exhaustion.
    /// Reset timestamps are reported in UTC; unknown or malformed values leave the reset unspecified.
    public static func failure(inErrorBody body: [UInt8], status: Int, headers: [String: String]) -> ProviderFailure? {
        let prefix = "anthropic-ratelimit-unified-"
        guard status == 429, headers[prefix + "overage-status"] != "allowed" else {
            return failure(inErrorBody: body)
        }
        // @dl:disable near-clone -- this provider's quota-name table is unrelated to sandbox test path tables
        var message = ""
        for (window, label) in [
            ("7d-", "weekly"), ("7d-sonnet-", "weekly Sonnet"), ("7d-opus-", "weekly Opus"),
            ("5h-", "five-hour"), ("", "account")
        ] where headers[prefix + window + "status"] == "rejected" {
            // @dl:enable near-clone
            if !message.isEmpty { message += " " }
            message += "The \(label) usage limit rejected this request."
            if let raw = headers[prefix + window + "reset"], raw.count <= 12,
                !raw.isEmpty, raw.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                let seconds = Int64(raw), seconds > 0, seconds <= 253_402_300_799
            {
                message += " Resets at " + Date(timeIntervalSince1970: Double(seconds)).ISO8601Format() + " (UTC)."
            }
        }
        guard !message.isEmpty else { return failure(inErrorBody: body) }
        if headers[prefix + "overage-disabled-reason"] == "org_level_disabled" {
            message += " Paid overage is disabled by your organization."
        } else if headers[prefix + "overage-status"] == "rejected" {
            message += " Paid overage is unavailable for this request."
        }
        message += " Wait for the rejected quotas to reset or use another account/provider; do not retry immediately."
        return ProviderFailure(kind: .usageLimit, message: message)
    }
}
