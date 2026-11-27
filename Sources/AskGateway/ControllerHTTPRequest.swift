internal import Foundation

/// One opening HTTP/1.1 request on the gateway's controllers door (`127.0.0.1`, ADR-0170): either a WebSocket upgrade for `/socket`
/// or a `GET`/`HEAD` request for one of the signed shell's static files, with the headers needed to check Cloudflare Access.
package enum ControllerHTTPRequest: Sendable, Equatable {
    package enum Kind: Sendable, Equatable {
        case webSocket(WebSocketHandshake, leftover: [UInt8])
        case http(method: String, path: String, headers: [String: String])
    }

    package enum Refusal: Error, Equatable {
        case incomplete
        case tooLarge
        case malformed
        case methodNotAllowed
        case badWebSocket(WebSocketHandshake.Refusal)
    }

    /// Parses the request at the start of `bytes`.
    package static func parse(_ bytes: [UInt8]) throws(Refusal) -> Kind {
        let parsed: WebSocketHandshake.RequestHead
        do {
            parsed = try WebSocketHandshake.readRequest(bytes)
        } catch .incomplete {
            throw .incomplete
        } catch .tooLarge {
            throw .tooLarge
        } catch {
            throw .malformed
        }
        if parsed.headers["upgrade"]?.lowercased() == "websocket" {
            do {
                let (handshake, used) = try WebSocketHandshake.parse(bytes)
                return .webSocket(handshake, leftover: Array(bytes[used...]))
            } catch {
                throw .badWebSocket(error)
            }
        }
        guard parsed.method == "GET" || parsed.method == "HEAD" else { throw .methodNotAllowed }
        let path =
            parsed.target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
            ?? "/"
        return .http(method: parsed.method, path: path, headers: parsed.headers)
    }

    /// Extracts the Cloudflare Access token from `Cf-Access-Jwt-Assertion` or the `CF_Authorization` cookie.
    package static func accessToken(in headers: [String: String]) -> String? {
        if let assertion = headers["cf-access-jwt-assertion"]?.trimmingCharacters(in: .whitespaces), !assertion.isEmpty
        {
            return assertion
        }
        guard let cookies = headers["cookie"] else { return nil }
        for part in cookies.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("CF_Authorization=") {
                let value = String(trimmed.dropFirst("CF_Authorization=".count))
                if !value.isEmpty { return value }
            }
        }
        return nil
    }
}
