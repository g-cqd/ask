# Security policy

ask runs a language model's tool calls inside a macOS Seatbelt sandbox by
default and keeps credentials (API keys, OAuth tokens from `ask login`) in
`~/.config/ask`. If you found a way for a model, an extension or a crafted
input to escape the sandbox, reach a secret store, or read another project's
files, please report it privately: use GitHub's *Report a vulnerability*
button on the Security tab of this repository, or open a security advisory.
Do not open a public issue for it.

Include the ask version (`ask --version`), the sandbox configuration if any
(`--no-sandbox`, a `sandbox` section in `config.json`), and a minimal
reproduction. Reports that reach a secret store (`~/.aws`, `~/.gnupg`,
Keychains, `~/.netrc`, ssh private keys, `~/.config/ask` itself) are treated
as high severity.
