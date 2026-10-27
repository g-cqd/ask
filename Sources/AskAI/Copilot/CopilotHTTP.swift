internal import AemiJSON
internal import Foundation

/// Bounded, redirect-refusing JSON requests. Provider bodies and transport descriptions never reach errors.
struct CopilotHTTP: Sendable {
    let transport: any HTTPTransport

    func json<T: Decodable>(_ request: HTTPRequest, as type: T.Type, limit: Int = 65_536) async throws(SignInError) -> T
    {
        do {
            try Task.checkCancellation()
            let response = try await transport.collecting(request, limit: limit)
            guard (200 ..< 300).contains(response.status) else { throw SignInError.rejected(status: response.status) }
            do { return try AemiJSON.JSONDecoder().decode(type, from: response.body) } catch {
                throw SignInError.invalidResponse("Copilot JSON")
            }
        } catch let error as SignInError { throw error } catch is CancellationError { throw .cancelled } catch {
            throw .transport("Copilot network request failed")
        }
    }

    func form<T: Decodable>(_ path: String, values: [(String, String)], as type: T.Type) async throws(SignInError) -> T
    {
        let body = FormEncoding.query(values)
        return try await json(
            HTTPRequest(
                url: URL(string: "https://github.com/\(path)")!, method: "POST",
                headers: [
                    ("accept", "application/json"), ("content-type", "application/x-www-form-urlencoded"),
                    ("user-agent", CopilotProtocol.userAgent)
                ],
                body: Array(body.utf8), allowsRedirects: false), as: type)
    }
}
