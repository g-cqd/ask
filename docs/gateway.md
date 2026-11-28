# The gateway

The gateway lets you reach the ask sessions of your computers from a browser: each computer with sessions (a **node**) connects
out to a **gateway** on your local network, and you open the gateway's signed web shell from anywhere through a Cloudflare Tunnel
behind Cloudflare Access. ADR-0170 and [the wire protocol](protocol/gateway.md) record how it works.

Session lists and terminal streams are encrypted end to end (Noise `N` and Noise `IK`): neither Cloudflare nor the gateway holds a
session key.

## 1. Set up the gateway computer

Generate the gateway's static key (kept in its Keychain) and note the `Key:` value for your nodes' `gateway.key`:

```sh
ask gateway server-fingerprint
```

Prepare and sign the static web shell (`GatewayShell/`):

```sh
./GatewayShell/install-vendor.sh
ask gateway sign-shell --shell-dir ./GatewayShell
```

Note the `Fingerprint:` printed by `sign-shell`: the browser's Service Worker pins that Ed25519 release key on first visit and
refuses any future shell update signed by another key.

Enroll each computer allowed to feed sessions to the gateway (using the `Key:` printed by `ask gateway fingerprint` on that
computer):

```sh
ask gateway enroll NODE_PUBLIC_KEY --label "laptop"
ask gateway nodes
ask gateway unenroll FINGERPRINT
```

Run the gateway with its two strictly separated doors — nodes on an explicit LAN IPv4 interface (never `0.0.0.0`, optionally
narrowed by `--nodes-cidr`), and controllers on `127.0.0.1` only (forwarded by `cloudflared`):

```sh
ask gateway serve \
  --nodes-listen 192.168.1.20:7443 \
  --nodes-cidr 192.168.1.0/24 \
  --controllers-port 8787 \
  --access-team your-team \
  --access-aud YOUR_ACCESS_AUD_TAG \
  --shell-dir ./GatewayShell
```

Every HTTP and WebSocket request on `127.0.0.1:8787` must carry a valid `Cf-Access-Jwt-Assertion` signed by your Cloudflare Access
team's keys (`--insecure-local-no-access` skips that check for local loopback testing only).

## 2. Set up each computer with sessions (a node)

Show this computer's node key (kept in its Keychain) and enroll it on the gateway as above:

```sh
ask gateway fingerprint
```

Enable sharing in `~/.config/ask/config.json` (see [configuration](configuration.md#gateway)):

```json
{
  "gateway": {
    "enabled": true,
    "address": "192.168.1.20:7443",
    "key": "BASE64_FROM_SERVER_FINGERPRINT",
    "folders": ["~/Developer"]
  }
}
```

With `gateway.enabled` on, each interactive `ask` offers its screen on an owner-only socket at
`~/.local/state/ask/gateway/viewers/<pid>.sock`. Run the node agent to link out to the gateway and relay channels to those
sockets:

```sh
ask gateway node
```

## 3. Trust a browser controller

Open the gateway's URL in your browser, unlock or create your controller key with a passphrase (stretched in the page with
Argon2id at 64 MiB and 3 passes into a non-extractable WebCrypto X25519 key) or a 32-byte `.key` file, verify the pinned shell
fingerprint in the top bar, and copy the `ask gateway trust` command onto each computer whose sessions that browser may open:

```sh
ask gateway trust CONTROLLER_PUBLIC_KEY --label "Browser"
ask gateway list
ask gateway untrust FINGERPRINT
```

`untrust` revokes a controller: new channels from it are refused at once, and every trust, attach and refusal is recorded in the
security audit log by fingerprint.

## 4. Run under `launchd`

Generate a user-agent property list (`~/Library/LaunchAgents/studio.aemi.ask.gateway.<role>.plist`):

```sh
ask gateway launchd --role node > ~/Library/LaunchAgents/studio.aemi.ask.gateway.node.plist
ask gateway launchd --role serve \
  --nodes-listen 192.168.1.20:7443 \
  --nodes-cidr 192.168.1.0/24 \
  --controllers-port 8787 \
  --access-team your-team \
  --access-aud YOUR_ACCESS_AUD_TAG \
  --shell-dir /path/to/GatewayShell \
  > ~/Library/LaunchAgents/studio.aemi.ask.gateway.server.plist
```
