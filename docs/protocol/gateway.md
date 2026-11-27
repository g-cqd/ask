# The ask gateway protocol — version 1 (draft)

How a computer with sessions (a **node**), the **gateway**, and a browser's shell (a **controller**) talk, as ADR-0170 decides.
**Draft**: fixed when the gateway first ships; changes after that are new versions, never edits.

## Layers

```
controller ──WebSocket (TLS, Cloudflare)── gateway ──TCP (LAN)── node
     └──────────── Noise IK, end to end, one per channel ───────────┘
                     gateway ── Noise XX ── node
```

1. **Node and gateway**: TCP, then Noise `XX_25519_ChaChaPoly_SHA256`, the prologue `ask-gateway/1 node`. Each Noise message on
   the wire is its length, 2 bytes big-endian, then the message (at most 65,535 bytes).
2. **Controller and gateway**: a WebSocket, one binary message per frame (below), behind Cloudflare Access. It is not
   encrypted beyond TLS: everything private in it is sealed end to end.
3. **Controller and node**: Noise `IK_25519_ChaChaPoly_SHA256` per channel, the prologue `ask-gateway/1 channel`, its messages
   carried in `open` and `data` frames. The gateway relays them and cannot read them.

## Relay frames

What the gateway reads: inside the node's Noise channel, and as WebSocket messages from a controller. Every integer is big-endian.

```
+------+---------------+------------------+
| kind | channel (u32) | body (the rest)  |
| 1 B  | 4 B           | 0 to 65,514 B    |
+------+---------------+------------------+
```

| Kind | Name | From | Body |
|---|---|---|---|
| `0x01` | `hello` | node, controller | version (u16, `1`), then a role byte: `1` node, `2` controller. Channel 0. |
| `0x02` | `list` | node | the node's sealed list (below). Channel 0. The gateway keeps the last one and gives it to controllers. |
| `0x03` | `lists` | gateway | to a controller: each known node as its static key (32 B), its list's length (u32), its sealed list. Channel 0. |
| `0x10` | `open` | controller, gateway | a new channel, numbered by the controller (odd numbers) and renumbered by the gateway for the node: the node's static key (32 B, from the controller only), then the controller's first IK message. |
| `0x11` | `data` | any | one Noise transport message of the channel, or the node's IK answer as the channel's first `data`. |
| `0x12` | `close` | any | a reason byte (`0` done, `1` refused, `2` node gone, `3` too many, `4` protocol error), then UTF-8 words for a person, at most 256 B. |
| `0x20` | `ping` | any | 8 bytes, echoed in `pong`. Channel 0. |
| `0x21` | `pong` | any | the 8 bytes of the `ping`. Channel 0. |

A frame shorter than 5 bytes, of an unknown kind, longer than 65,519 bytes (so that a whole frame is one Noise message), or whose body breaks its kind's shape ends the connection
with `close` reason `4`. Channel 0 carries only `hello`, `list`, `lists`, `ping`, `pong`; every other kind names a channel above 0.

## The sealed list

What a node shares: its sessions' names, folders and states. Sealed to each trusted controller key, so the gateway forwards it
unread. For each controller, in turn:

```
+--------------------+--------------+----------------------------------+
| fingerprint (8 B)  | length (u32) | N message (length bytes, >= 48)  |
+--------------------+--------------+----------------------------------+
```

The fingerprint is the first 8 bytes of SHA-256 of the controller's public key; the message is a Noise `N_25519_ChaChaPoly_SHA256`
message to that key, the prologue `ask-gateway/1 list`, a fresh ephemeral key for each, whose payload is the list as JSON (at most
65,487 bytes). A controller opens the entry with its fingerprint and ignores the others.

The payload JSON is an object with two arrays (`SharedNodeList`):

```json
{
  "sessions": [
    {
      "id": "4242",
      "folder": "/srv/project",
      "label": "claude-sonnet-5-5",
      "started": "2026-11-27T00:00:00Z"
    }
  ],
  "folders": ["/srv/project"]
}
```

`folders` lists the canonical directories a controller may pass to `start` (`gateway.folders`, empty when `policy.gatewayStart` is
`false` or none is configured).

## Channel messages

Inside a channel's Noise transport, after the handshake: one message per Noise message, a kind byte and a body.

| Kind | Name | From | Body |
|---|---|---|---|
| `0x01` | `attach` | controller | columns (u16), rows (u16), then the session's id, UTF-8. The node starts a screen for this viewer. |
| `0x02` | `start` | controller | columns (u16), rows (u16), then a folder the node lists, UTF-8. A new session, attached. |
| `0x03` | `input` | controller | bytes as a terminal sends them: keys, pastes, mouse, focus. |
| `0x04` | `resize` | controller | columns (u16), rows (u16). |
| `0x10` | `output` | node | bytes as a terminal receives them, in order. |
| `0x11` | `ended` | node | UTF-8 words: the session ended or was closed at the node. |
| `0x12` | `refused` | node | UTF-8 words: what was asked is not allowed (policy, an unknown session or folder). |

Columns and rows are 1 to 1,000. A channel's Noise message travels as a relay frame's body, so it is at most 65,514 bytes: a
message carries at most 65,497 bytes of output, and more is split; output is a byte stream.
