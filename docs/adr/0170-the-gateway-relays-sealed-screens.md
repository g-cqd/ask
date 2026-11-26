---
status: accepted
date: 2026-11-26
---

# 0170 — The gateway relays sealed screens

## Context

The owner wants to reach the ask sessions of the computers at home from any browser: a laptop has the sessions, an always-on Mac
hosts a gateway, and the gateway is reached from outside through a Cloudflare Tunnel. A key is required to open the dashboard, which lists every
session the gateway knows; choosing one makes the page a terminal for that session, used as a terminal is.

The owner decided (2026-11-26):

- **The browser shows ask's own screen**, rendered for the browser's size, from the same live conversation.
- **End to end**: only the computer that holds a session and the keys the owner trusts can read it; the gateway and Cloudflare relay.
- **The key** is held three ways, any of which opens the dashboard: a passkey (WebAuthn PRF), a passphrase, or a key file.
- **The page's code is pinned**: an installed shell refuses code not signed by the owner's release key.
- **Cloudflare Access is in front** of the tunnel.
- **A controller may** watch, type and steer, answer approvals, and start sessions.
- **Sharing**: once a computer's gateway sharing is on, all its sessions are shared.

## Decision

### Parts

| Part | Runs on | Is |
|---|---|---|
| **node** | each computer with sessions | `ask` itself: `gateway.enabled` makes every ask on the computer offer its sessions to a local node agent, which holds one outbound connection to the gateway |
| **gateway** | the always-on Mac | a small relay: it accepts nodes on the LAN, accepts browsers on loopback (through `cloudflared`), and routes sealed frames between them; it never holds a session key |
| **shell** | the browser | a static, signed web app: key handling, the dashboard, and a terminal emulator |

The screen a browser sees is ask's screen, **rendered on the node**: the session's conversation (the `Conversation` seam ADR-0154
serves) drives one more `ScreenSession` per viewer, composed at that viewer's size. The browser receives the bytes a terminal would,
and sends keys, pastes, mouse and resize as a terminal does. The local terminal is never resized by a viewer, and nothing in ask's
core learns there is a browser.

### Two doors, never one

The gateway listens twice:

1. **Nodes** on a configured LAN interface and port only (`gateway.listen.nodes`, such as `en0` and a CIDR), mutually
   authenticated by keys (below). This door is never in the tunnel's configuration.
2. **Controllers** on `127.0.0.1` only; `cloudflared` beside the gateway forwards the tunnel's hostname to it. Cloudflare Access (SSO
   or a one-time email code, with device rules if wanted) admits a person before any byte reaches the gateway, which checks Access's
   signed assertion (`Cf-Access-Jwt-Assertion`) against the team's keys as well, so a request around the tunnel is refused.

Nodes dial out: a computer with sessions opens no port.

### Keys

- **Each node** has an identity: an X25519 key for agreement and an Ed25519 key for signing, its private halves in the Keychain
  (ADR-0110), non-exportable where the platform allows.
- **Each controller** (the owner, on any browser) is one X25519 key pair, derived or unwrapped in the shell:
  - a **passkey** with the WebAuthn PRF extension: the PRF output is the input of HKDF to the private key; nothing to type;
  - a **passphrase**, stretched with Argon2id at ADR-0169's parameters in the shell, for a browser without passkeys, and as recovery;
  - a **key file**, imported once and kept as a non-extractable WebCrypto key.
  All three open the same controller key: the passkey and the passphrase each wrap it, and the wrapped forms live on the gateway,
  which cannot open them.
- **Trust** is explicit on each node: `ask gateway trust FINGERPRINT` adds a controller's public key; `ask gateway untrust` removes it
  at once, ending its live connections. The gateway knows nodes by their public keys (`ask gateway enroll` beside the gateway approves one).

### Channels

- **Node and gateway**: Noise `XX` over TCP (X25519, ChaCha20-Poly1305, SHA-256), both static keys checked against the enrolment.
- **Controller and node, through the gateway**: Noise `IK` end to end, the controller knowing the node's key from the dashboard's
  signed list; the gateway sees which node and which channel, sizes and times, never the content. Each session viewed is its own
  channel, keyed apart, so revoking one viewer ends only its channels.
- **The dashboard list** (names, folders, states of sessions) is sealed by each node to every trusted controller key, so the gateway
  stores and forwards it without reading it.

### What a controller may do

Watch, type and steer, answer questions and approvals, and start a session in a folder the node lists (`gateway.folders`), all as
the local person may; the node's sandbox, approvals and managed policy are the same as at the keyboard. Every remote action is in the
node's `SecurityAuditLog` with the controller's fingerprint. Managed configuration may narrow it (`policy.gatewayAllowed`,
`policy.gatewayApprovals`, `policy.gatewayStart`), and requirements win (ADR-0168).

### The shell

Static files, built and signed with the owner's release key. On first visit the page installs a service worker that holds the
release public key; from then on it serves only files whose signed manifest verifies, and refuses an update that does not. The first
visit is trust on first use: the owner checks the key's fingerprint the shell shows against `ask gateway fingerprint` once per
browser. Sunset may carry the shell built in, with no first visit at all.

## Consequences

- A gateway taken over learns which nodes are up, who connects and how much flows; it can drop or delay frames, not read or forge them.
- Cloudflare terminates TLS and sees only sealed frames, since every frame inside is end to end.
- The weak point is the browser: a controller key opened in a compromised browser reads what that browser reads. The passkey keeps
  the key bound to a device and a touch; the passphrase is the recovery, and should be long.
- Rendering per viewer costs the node one composer per viewer, at the screen's own budgets; measured before a viewer limit is set.
- New code: the node agent and protocol in ask (a module beside `AskACP`), the gateway (a separate executable product), the shell
  (web, in its own repository), and a terminal emulator in the shell (xterm.js-class, to choose after a probe).
- Sharing all sessions of a computer means a new session is offered the moment it starts; `gateway.enabled` off stops all at once.

## Open

- The wire format of the relay frames, and of the sealed list, in `docs/protocol/gateway.md`, fixed before the first release.
- Whether the gateway is Swift on the family's `HTTP` package, or a smaller relay; decided by a probe of both on the gateway's computer.
- How a session closed locally while viewed remotely ends for the viewer (proposal: the viewer is told, and the channel ends).
