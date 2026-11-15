/// What a client opens with (ACP v1, Initialization). Only what ask reads so far: the version, which must be there.
struct ACPInitializeParams: Decodable {
    let protocolVersion: Int
}
