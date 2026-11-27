# The gateway

The gateway lets you reach the ask sessions of your computers from a browser: each computer with sessions connects to a gateway
on your network, and you open the gateway's page from anywhere through a Cloudflare Tunnel. ADR-0170 records how it works.

Only this computer's side exists so far: its key, the controllers it trusts, and the socket each ask offers its screen on. The
gateway and its page are not available yet.

## This computer's key

```sh
ask gateway fingerprint
```

shows this computer's public key and its fingerprint, eight groups of four hex digits. The key is made the first time and kept in
your keychain; the private half never leaves it. Compare the fingerprint with the one a controller shows before you trust it with
anything.

## Trusting a controller

A controller is a key held in one of your browsers. Only a controller this computer trusts can open one of its sessions.

```sh
ask gateway trust KEY --label "Safari on the laptop"
ask gateway list
ask gateway untrust FINGERPRINT
```

- `trust` takes the controller's public key, as base64 or 64 hex digits.
- `untrust` takes the key, or the first 8 digits or more of its fingerprint, spaces ignored. A start that matches two controllers
  removes neither.
- The list is kept in `~/.config/ask/gateway/trusted.json` (owner-only), and each change is written to the security audit log,
  with the fingerprint, never the key.

## What a shared session offers

With `gateway.enabled` on (see [configuration](configuration.md#gateway)), each interactive ask offers its screen on a socket of
its own, `~/.local/state/ask/gateway/viewers/<process id>.sock`, with `<process id>.json` beside it naming the folder and the
model. The folder and the socket are yours alone, and a connection from another user is refused. A viewer attached there sees
the screen at its own size and types into it, sharing it with you: the same input line, the same place. Each viewer that
attaches is written to the security audit log. The socket goes when ask closes.

