/// Who a stored sign-in is, as its provider reports it: a Codex account id, or a Claude account address.
public enum AccountIdentity: Sendable, Equatable {
    case codex(String)
    case claude(String)
}
