---
status: not-started
blocked-by: []
date: 2026-11-01
---

# 0182 — Session files compressed, encrypted, or both

Wish (2026-11-01): settings to compress and, separately, to encrypt session files, with a password whose key lives in the keychain,
so sessions are unreadable outside ask. Global or per workspace (the workspace overriding); the password saved or asked at every
start; or ask at each start whether this conversation is encrypted; and `/encrypt on|off`.

## Design

ADR-0138 (accepted, 2026-11-01): plain JSONL when both settings are off; otherwise a framed container with zlib sync-flushed deflate and
AES-256-GCM frames, a per-file data key wrapped by a user key, the user key wrapped by an Argon2id password (aemi's AemiArgon2) and a
recovery key, and optionally kept in the keychain. Asked at first start; a workspace overrides either way. The same container holds the
task and idea store (0179, 0180).

## Phases

1. ~~The container: frames, compression, encryption under a given key, recovery of torn and damaged files (AskAgentCore).~~ Done,
   2026-11-01: `Sources/AskAgentCore/Storage/`, 11 tests (each mode, reopening, a cut at every byte of the last frame, every changed
   byte of a frame before it and of the header, reordered, dropped and moved frames, nonces), and a mutation of each of the eight guards
   turns them red.
2. Keys: the user key, `keys.json` (Argon2id, the recovery key), the keychain when remembered.
3. Session files on the container: the settings, the first-start question, `/encrypt`, locked sessions in lists and resume.

## Still owed

- ~~A design record~~ (ADR-0138): the format (a framed, appendable file, since sessions are written as they grow), the cipher (CryptoKit
  `ChaChaPoly` or AES-GCM), the key from the password (a KDF with a stored salt), what is kept in the keychain (0110), and what happens
  to `/tree`, `/fork` and resume when the key is missing.
- Compression on its own: zlib with a sync flush per record, not Apple's Compression framework (no flush point; ADR-0138).
- Settings typed (0118), and the `/encrypt` command.
