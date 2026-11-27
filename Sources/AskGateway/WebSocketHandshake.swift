internal import CryptoKit
internal import Foundation

/// The opening of a WebSocket (RFC 6455, section 4.2), as the gateway's controllers' door reads it: one HTTP request, at most 16 KiB of
/// headers, answered with 101 Switching Protocols when it asks for a version 13 WebSocket, or refused.
package struct WebSocketHandshake: Sendable, Equatable {
    /// Why an opening was refused.
    package enum Refusal: Error, Equatable {
        case incomplete
        case tooLarge
        case notAWebSocket
        case wrongVersion
        case missingKey
    }

    /// The request's path, such as `/` or `/socket`.
    package let path: String
    /// The request's headers, names lowercased; a repeated name keeps its last value.
    package let headers: [String: String]
    /// The client's `Sec-WebSocket-Key`.
    package let key: String

    /// The largest header block read before the opening is refused.
    package static let largest = 16_384

    struct RequestHead {
        let method: String
        let target: String
        let headers: [String: String]
        let end: Int
    }

    /// Reads the HTTP/1.1 request line, lowercased headers, and header block byte length from `bytes`.
    static func readRequest(_ bytes: [UInt8]) throws(Refusal) -> RequestHead {
        guard let end = headerEnd(bytes) else { throw bytes.count > largest ? .tooLarge : .incomplete }
        guard end <= largest else { throw .tooLarge }
        let text = String(decoding: bytes[..<end], as: UTF8.self)
        var lines = text.components(separatedBy: "\r\n")
        let request = lines.removeFirst().split(separator: " ")
        guard request.count == 3, request[2].hasPrefix("HTTP/1.1") else { throw .notAWebSocket }
        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { throw .notAWebSocket }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
        }
        return RequestHead(method: String(request[0]), target: String(request[1]), headers: headers, end: end)
    }

    /// The handshake at the start of `bytes`, and how many bytes it took; ``Refusal/incomplete`` while the headers have not ended.
    package static func parse(_ bytes: [UInt8]) throws(Refusal) -> (handshake: WebSocketHandshake, length: Int) {
        let head = try readRequest(bytes)
        guard head.method == "GET",
            head.headers["upgrade"]?.lowercased() == "websocket",
            head.headers["connection"]?.lowercased().split(separator: ",")
                .contains(where: { $0.trimmingCharacters(in: .whitespaces) == "upgrade" })
                == true
        else { throw .notAWebSocket }
        guard head.headers["sec-websocket-version"] == "13" else { throw .wrongVersion }
        guard let key = head.headers["sec-websocket-key"], Data(base64Encoded: key)?.count == 16 else {
            throw .missingKey
        }
        return (WebSocketHandshake(path: head.target, headers: head.headers, key: key), head.end)
    }

    /// The `Sec-WebSocket-Accept` for `key`.
    package static func accept(for key: String) -> String {
        Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))).base64EncodedString()
    }

    /// The 101 answer that opens the WebSocket.
    package var answer: [UInt8] {
        Array(
            ("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                + "Sec-WebSocket-Accept: \(Self.accept(for: key))\r\n\r\n")
                .utf8
        )
    }

    /// Where the header block ends: past the first empty line.
    private static func headerEnd(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 4 else { return nil }
        for index in 3 ..< bytes.count
        where bytes[index - 3] == 0x0D && bytes[index - 2] == 0x0A && bytes[index - 1] == 0x0D && bytes[index] == 0x0A {
            return index + 1
        }
        return nil
    }
}
