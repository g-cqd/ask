internal import AemiJSON
internal import Foundation

/// Pin inference to the current credential origin and path, and sanitize untrusted error bodies before generic decoders see them.
struct CopilotTransport: HTTPTransport {
    let inner: any HTTPTransport
    let url: URL

    func send(_ request: HTTPRequest) async throws -> HTTPStreamingResponse {
        guard request.url == url, !request.allowsRedirects else {
            throw SignInError.invalidResponse("Copilot inference endpoint")
        }
        let response: HTTPStreamingResponse
        do { response = try await inner.send(request) } catch is CancellationError { throw CancellationError() } catch {
            throw SignInError.transport("Copilot inference network request failed")
        }
        guard !(200 ..< 300).contains(response.status) else { return response }
        let message: String
        switch response.status {
            case 401: message = "Copilot sign-in expired; use /login copilot-vscode."
            case 402: message = "Copilot billing or budget refused this request."
            case 403: message = "Copilot entitlement or organization/model policy refused this request."
            case 429: message = "Copilot quota or rate limit reached."
            default: message = "Copilot request failed (HTTP \(response.status))."
        }
        let bytes = JSONStreamWriter.object(of: [("message", message)])
        return HTTPStreamingResponse(
            status: response.status, headers: ["content-type": "application/json"],
            body: AsyncThrowingStream { stream in
                stream.yield(bytes)
                stream.finish()
            })
    }
}
