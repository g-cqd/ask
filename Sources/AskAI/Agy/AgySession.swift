/// What a request to Cloud Code needs: a usable access token and the project it is made under.
public struct AgySession: Sendable, Equatable {
    public let accessToken: String
    public let projectID: String
}
