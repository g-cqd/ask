---
status: not-started
blocked-by: []
date: 2026-11-01
---

# 0182 — Session files compressed, encrypted, or both

Wish (2026-11-01): settings to compress and, separately, to encrypt session files, with a password whose key lives in the keychain,
so sessions are unreadable outside ask. Global or per workspace (the workspace overriding); the password saved or asked at every
start; or ask at each start whether this conversation is encrypted; and `/encrypt on|off`.

## Still owed

- A design record: the format (a framed, appendable file, since sessions are written as they grow), the cipher (CryptoKit
  `ChaChaPoly` or AES-GCM), the key from the password (a KDF with a stored salt), what is kept in the keychain (0110), and what happens
  to `/tree`, `/fork` and resume when the key is missing.
- Compression on its own: Apple's Compression framework, per frame so appends stay cheap.
- Settings typed (0118), and the `/encrypt` command.
