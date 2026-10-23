internal import AemiJSON

/// Reads the `error` code of an OAuth error body.
enum OAuthErrorBody {
    static func code(in body: [UInt8]) throws -> String? { try AemiJSON.parse(body).root["error"].string }
}
