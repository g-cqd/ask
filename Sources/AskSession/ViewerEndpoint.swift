internal import AemiJSON
internal import AskGateway
internal import AskTUI
internal import Darwin
internal import Foundation

/// Where the gateway's node reaches this process's screen (ADR-0170): an owner-only Unix socket, `<state>/gateway/viewers/<pid>.sock`,
/// with `<pid>.json` beside it saying what this session is. Each connection is one viewer: channel messages in plain length-prefixed
/// frames (the socket is the person's own, and the node seals them for the gateway), an `attach` first, then input and resizes in
/// and the screen's output back, through a pseudo-terminal of the viewer's size.
final class ViewerEndpoint: Sendable {
    /// What a node reads about this session, written beside the socket.
    struct Description: Codable, Sendable, Equatable {
        /// The id a node attaches by: this process's id, as text.
        let id: String
        /// The folder the session works in.
        let folder: String
        /// The model's label, as the status line shows it.
        let label: String
        /// When this process started sharing, ISO 8601.
        let started: String
    }

    let socketPath: String
    private let descriptionPath: String
    private let acceptor: SocketAcceptor

    /// Starts accepting viewers.
    /// - Parameters:
    ///   - folder: the folder where the endpoint's socket and description go, made owner-only.
    ///   - description: what a node reads about this session; its `id` is what an `attach` must name.
    ///   - audit: records each viewer that attaches and leaves, with the controller the node names.
    /// - Throws: ``TCPStream/Failure`` naming the call that failed.
    init(in folder: String, description: Description, audit: @escaping @Sendable (String, String) -> Void)
        throws(TCPStream.Failure)
    {
        try? FileManager.default.createDirectory(
            atPath: folder,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        _ = chmod(folder, 0o700)
        socketPath = folder + "/\(description.id).sock"
        descriptionPath = folder + "/\(description.id).json"
        let listener = try UnixSocket.listen(at: socketPath)
        let expected = description.id
        acceptor = try SocketAcceptor(listener: listener) { client in
            // The person's own processes only: a socket in an owner-only folder, and its peer checked again.
            var uid: uid_t = 0
            var gid: gid_t = 0
            guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else {
                Darwin.close(client)
                return
            }
            Task { await ViewerConnection.serve(TCPStream(descriptor: client), session: expected, audit: audit) }
        }
        let data = (try? AemiJSON.JSONEncoder().encodeToBytes(description)) ?? []
        FileManager.default.createFile(
            atPath: descriptionPath,
            contents: Data(data),
            attributes: [.posixPermissions: 0o600]
        )
    }

    /// Stops accepting, and removes the socket and the description so no node lists this session again.
    func stop() {
        acceptor.stop()
        unlink(socketPath)
        unlink(descriptionPath)
    }
}
