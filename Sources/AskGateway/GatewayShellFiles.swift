internal import Darwin
internal import Foundation

/// Serves the signed web shell's static files from a folder on disk (ADR-0170), confined by `realpath` and accompanied by strict
/// browser isolation headers so no external script, frame or origin can run in the page.
package struct GatewayShellFiles: Sendable {
    private let root: String?

    /// `directory`: the folder holding `index.html`, `sw.js`, `manifest.json`, `manifest.sig` and the shell's assets; nil serves a
    /// plain status page saying no shell bundle was given.
    package init(directory: String?) {
        if let directory, let resolved = realpath(directory, nil) {
            defer { free(resolved) }
            root = String(cString: resolved)
        } else {
            root = nil
        }
    }

    /// Builds a complete HTTP/1.1 response for `method` (`GET` or `HEAD`) and `path`.
    package func response(method: String, path: String) -> [UInt8] {
        let relative = path == "/" ? "/index.html" : path
        guard relative.hasPrefix("/"),
            !relative.contains(".."),
            !relative.contains("\\"),
            !relative.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
        else {
            return Self.http(
                status: "400 Bad Request",
                contentType: "text/plain; charset=utf-8",
                body: [],
                headOnly: method == "HEAD"
            )
        }
        guard let root else {
            let body = Array("ask gateway is running; pass --shell-dir to serve the signed web shell.\n".utf8)
            let status = relative == "/index.html" ? "200 OK" : "404 Not Found"
            return Self.http(
                status: status,
                contentType: "text/plain; charset=utf-8",
                body: status == "200 OK" ? body : [],
                headOnly: method == "HEAD"
            )
        }
        let candidate = root + relative
        guard let resolvedPointer = realpath(candidate, nil) else {
            return Self.http(
                status: "404 Not Found",
                contentType: "text/plain; charset=utf-8",
                body: [],
                headOnly: method == "HEAD"
            )
        }
        defer { free(resolvedPointer) }
        let resolved = String(cString: resolvedPointer)
        var info = stat()
        guard resolved == root || resolved.hasPrefix(root + "/"),
            stat(resolved, &info) == 0,
            (info.st_mode & S_IFMT) == S_IFREG,
            let data = FileManager.default.contents(atPath: resolved)
        else {
            return Self.http(
                status: "404 Not Found",
                contentType: "text/plain; charset=utf-8",
                body: [],
                headOnly: method == "HEAD"
            )
        }
        return Self.http(
            status: "200 OK",
            contentType: Self.contentType(for: resolved),
            body: Array(data),
            headOnly: method == "HEAD"
        )
    }

    /// Complete HTTP/1.1 response with strict security headers, also used for 403/405 refusals before upgrade.
    package static func http(
        status: String,
        contentType: String = "text/plain; charset=utf-8",
        body: [UInt8] = [],
        headOnly: Bool = false
    ) -> [UInt8] {
        let headers =
            "HTTP/1.1 \(status)\r\n"
            + "Content-Type: \(contentType)\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: close\r\n"
            + "Cache-Control: no-store\r\n"
            + "X-Content-Type-Options: nosniff\r\n"
            + "Referrer-Policy: no-referrer\r\n"
            + "Cross-Origin-Opener-Policy: same-origin\r\n"
            + "Cross-Origin-Resource-Policy: same-origin\r\n"
            + "Content-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; "
            + "img-src 'self' data:; font-src 'self'; worker-src 'self'; manifest-src 'self'; base-uri 'none'; "
            + "form-action 'none'; frame-ancestors 'none'\r\n\r\n"
        return Array(headers.utf8) + (headOnly ? [] : body)
    }

    private static func contentType(for path: String) -> String {
        let lower = (path as NSString).pathExtension.lowercased()
        switch lower {
            case "html": return "text/html; charset=utf-8"
            case "js", "mjs": return "text/javascript; charset=utf-8"
            case "css": return "text/css; charset=utf-8"
            case "json": return "application/json; charset=utf-8"
            case "wasm": return "application/wasm"
            case "svg": return "image/svg+xml"
            case "png": return "image/png"
            case "sig", "bin": return "application/octet-stream"
            default: return "application/octet-stream"
        }
    }
}
