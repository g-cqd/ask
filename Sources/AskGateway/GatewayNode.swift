package import CryptoKit

/// A node's side of the gateway protocol (ADR-0170), with no network: relay frames from the gateway in, relay frames to it out, and
/// what controllers ask as events for the node's host, which owns the sessions and their screens. Each channel is end to end
/// (``NodeChannel``); a controller this node does not trust is refused when it opens one, before anything else is read.
package struct GatewayNode: Sendable {
    /// What a controller asks of the node's host, on a channel.
    package enum Event: Sendable, Equatable {
        case attach(channel: UInt32, size: ChannelMessage.Size, session: String, controller: String)
        case start(channel: UInt32, size: ChannelMessage.Size, folder: String, controller: String)
        case input(channel: UInt32, bytes: [UInt8])
        case resize(channel: UInt32, size: ChannelMessage.Size)
        /// The channel ended: by the controller, the gateway, or a message that did not open.
        case closed(channel: UInt32)
    }

    private let key: Curve25519.KeyAgreement.PrivateKey
    private let trusts: @Sendable (Curve25519.KeyAgreement.PublicKey) -> Bool
    private var channels: [UInt32: NodeChannel] = [:]

    /// - Parameters:
    ///   - key: this node's static key.
    ///   - trusts: whether a controller key is trusted, asked when a channel opens, so `ask gateway untrust` takes effect at the next.
    package init(
        key: Curve25519.KeyAgreement.PrivateKey,
        trusts: @escaping @Sendable (Curve25519.KeyAgreement.PublicKey) -> Bool
    ) {
        self.key = key
        self.trusts = trusts
    }

    /// The node's `hello`, the first frame on its connection.
    package static var hello: RelayFrame { RelayFrame(checked: .hello, channel: 0, body: [0, 1, 1]) }

    /// The node's list, sealed to each of `controllers`, as a `list` frame.
    package static func list(_ json: [UInt8], to controllers: [Curve25519.KeyAgreement.PublicKey]) throws(SealedList
        .Failure)
        -> RelayFrame
    {
        RelayFrame(checked: .list, channel: 0, body: try SealedList.seal(json, to: controllers))
    }

    /// The channels open now.
    package var openChannels: Set<UInt32> { Set(channels.keys) }

    /// A frame from the gateway: the frames to answer with, and the events for the host.
    package mutating func receive(_ frame: RelayFrame) -> (frames: [RelayFrame], events: [Event]) {
        switch frame.kind {
            case .ping: return ([RelayFrame(checked: .pong, channel: 0, body: frame.body)], [])
            case .open: return open(frame)
            case .data:
                guard var channel = channels[frame.channel] else { return ([], []) }
                guard let message = try? channel.receive(frame.body) else {
                    channels[frame.channel] = nil
                    return (
                        [Self.close(frame.channel, reason: 4, "a message that did not open")],
                        [.closed(channel: frame.channel)]
                    )
                }
                channels[frame.channel] = channel
                return ([], event(message, on: frame.channel, from: channel).map { [$0] } ?? [])
            case .close:
                guard channels.removeValue(forKey: frame.channel) != nil else { return ([], []) }
                return ([], [.closed(channel: frame.channel)])
            default: return ([], [])
        }
    }

    /// The host's terminal bytes for the viewer on `channel`, sealed, split when large.
    package mutating func output(_ bytes: [UInt8], on channel: UInt32) -> [RelayFrame] {
        send(.output(bytes), on: channel)
    }

    /// The host refuses what `channel` asked, and the channel ends.
    package mutating func refuse(_ channel: UInt32, _ words: String) -> [RelayFrame] {
        let frames = send(.refused(words), on: channel)
        channels[channel] = nil
        return frames + [Self.close(channel, reason: 1, words)]
    }

    /// The session `channel` shows ended at the node, and the channel with it.
    package mutating func ended(_ channel: UInt32, _ words: String) -> [RelayFrame] {
        let frames = send(.ended(words), on: channel)
        channels[channel] = nil
        return frames + [Self.close(channel, reason: 0, words)]
    }

    private mutating func open(_ frame: RelayFrame) -> (frames: [RelayFrame], events: [Event]) {
        do {
            let (channel, answer) = try NodeChannel.accept(frame.body, nodeKey: key, trusts: trusts)
            channels[frame.channel] = channel
            return ([RelayFrame(checked: .data, channel: frame.channel, body: answer)], [])
        } catch .untrusted {
            return ([Self.close(frame.channel, reason: 1, "this computer does not trust that controller")], [])
        } catch {
            return ([Self.close(frame.channel, reason: 4, "an opening this computer cannot read")], [])
        }
    }

    private func event(_ message: ChannelMessage, on channel: UInt32, from end: NodeChannel) -> Event? {
        let controller = GatewayKeys.fingerprint(end.controller)
        switch message {
            case .attach(let size, let session):
                return .attach(channel: channel, size: size, session: session, controller: controller)
            case .start(let size, let folder):
                return .start(channel: channel, size: size, folder: folder, controller: controller)
            case .input(let bytes): return .input(channel: channel, bytes: bytes)
            case .resize(let size): return .resize(channel: channel, size: size)
            case .output, .ended, .refused: return nil
        }
    }

    private mutating func send(_ message: ChannelMessage, on channel: UInt32) -> [RelayFrame] {
        guard var end = channels[channel], let sealed = try? end.send(message) else { return [] }
        channels[channel] = end
        return sealed.map { RelayFrame(checked: .data, channel: channel, body: $0) }
    }

    private static func close(_ channel: UInt32, reason: UInt8, _ words: String) -> RelayFrame {
        // At most 256 bytes of words, cut between characters so they stay UTF-8.
        var kept = ""
        for character in words where kept.utf8.count + character.utf8.count <= 256 { kept.append(character) }
        return RelayFrame(checked: .close, channel: channel, body: [reason] + Array(kept.utf8))
    }
}
