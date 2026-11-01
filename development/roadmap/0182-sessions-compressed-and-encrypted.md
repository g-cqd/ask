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
2. ~~Keys: the user key, `keys.json` (Argon2id, the recovery key), the keychain when remembered.~~ Done, 2026-11-01:
   `Sources/AskAgentCore/Storage/Keys/`. 11 tests (password and recovery code, a code however typed, a password change, `keys.json`
   round-trip with no secret in it, each derivation bound alone, another version, the standard derivation, envelopes under their own
   user key only and unchanged, purposes kept apart, the keychain's key recalled only when it hashes to `keys.json`'s identifier); each
   of 12 guards, mutated, turns them red. A redundant identifier check the hash already makes was removed when its mutation survived.
3. Session files on the container: the settings, the first-start question, `/encrypt`, locked sessions in lists and resume.
   - ~~3a, the core~~ Done, 2026-11-01: `SessionFile` creates, opens, appends to, repairs, forks and changes the format of framed files
     (`format:`, `keyring:`), read a chunk at a time (`FrameScanner`), a record's decompressed size and the archive's capped; a torn or
     damaged frame is an issue, so the first change rewrites the file and keeps the original. `change(to:)` keeps no copy of the file
     as it was. 8 tests and 2 for the scanner; each of 9 guards, mutated, turns them red.
   - 3b, the app: the settings, `keys.json` and the keychain at start, the first-start question, the recovery code shown once,
     `/encrypt`, locked sessions in `/sessions`, `/tree` and resume, and a session's pictures encrypted with it.

## Still owed

- ~~A design record~~ (ADR-0138): the format (a framed, appendable file, since sessions are written as they grow), the cipher (CryptoKit
  `ChaChaPoly` or AES-GCM), the key from the password (a KDF with a stored salt), what is kept in the keychain (0110), and what happens
  to `/tree`, `/fork` and resume when the key is missing.
- Compression on its own: zlib with a sync flush per record, not Apple's Compression framework (no flush point; ADR-0138).
- Settings typed (0118), and the `/encrypt` command.
