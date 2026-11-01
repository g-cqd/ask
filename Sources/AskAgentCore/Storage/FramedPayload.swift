/// What a framed file's records are written in.
enum FramedPayload: UInt8, Equatable, Sendable {
    case json = 0
    case protobuf = 1
}
