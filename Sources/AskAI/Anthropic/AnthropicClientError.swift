/// Why an Anthropic request failed: a shared ``ProviderStreamError`` over the Anthropic decoder's failures.
public typealias AnthropicClientError = ProviderStreamError<AnthropicStreamError>
