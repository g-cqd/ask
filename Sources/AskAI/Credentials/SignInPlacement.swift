/// Where a sign-in without a name is stored (roadmap 0092): a second account of a provider is added beside the first, never put in
/// its place.
public enum SignInPlacement: Sendable, Equatable {
    /// The provider's default sign-in: it was empty, it held this account, or replacing it was asked for.
    case defaultSignIn
    /// The named connection that already holds this account, by its name.
    case connection(String)
    /// A new named connection, by the name chosen for it.
    case newConnection(String)
}
