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
   - ~~3b, the app~~ Done, 2026-11-01: `sessionEncryption` (`off`, `on`, `ask`), `sessionCompression`, `sessionPassword`
     (`remember`, `everyStart`), and `ASK_SESSION_ENCRYPTION` for scripts; before the screen, on the terminal: the first-start
     question (its answer kept in `session-encryption.json`, the settings winning over it), the password typed twice and the recovery
     code shown once, or the password asked (three tries, then the recovery code) unless the keychain holds the key; `--continue` and
     `--resume` unlock an encrypted session there; `/encrypt [on|off]`; `ask sessions` and `/resume` show a session without keys as
     locked; `ask keys password|forget`. `Scripts/probe-session-encryption.py` drives all of it through the release binary (10 checks).
     Every probe and measurement sets `ASK_SESSION_ENCRYPTION=off`, so none stops at the question.
   - ~~3c~~ Done, 2026-11-01: an encrypted session's pictures are sealed in the shared store under a key derived from the user key,
     named by an HMAC of their bytes rather than their hash; a reader without the key gets the line of text a missing picture leaves.
     2 tests; each of 4 guards, mutated, turns them red.

## Measured (2026-11-01, M3, release)

- A process that set up keys keeps 17.6 MiB resident once the screen is open, against 16.6 for a plain start, after aemi 8087a01 maps
  Argon2's memory (36.5 MiB before: a freed large malloc block stays resident). While a derivation runs, the peak is 33 MiB for about
  10 ms (19 MiB of Argon2id memory).
- `Scripts/measure-budgets.py`, this binary against f82148c (before this work), same load: idle memory 15.30 against 15.01 MiB (limit
  15.36); active memory 25.4 against 25.1–25.2 MiB; cold start and input delay vary run to run more than between the binaries (cold
  start 43.6 against 60.1 and 75.5 ms, input 10.15 against 6.6 and 10.1 ms). Active memory, input delay and cold start were already over
  their budgets at f82148c under this load.

## Still owed

- Plaintext left behind: after `/encrypt on`, pictures the session stored before stay in the shared store unencrypted (other sessions may
  name them); a rewritten file's old blocks may survive on an SSD or APFS until reused. Say so in the docs, or rewrite the pictures.

## Still owed

- ~~A design record~~ (ADR-0138): the format (a framed, appendable file, since sessions are written as they grow), the cipher (CryptoKit
  `ChaChaPoly` or AES-GCM), the key from the password (a KDF with a stored salt), what is kept in the keychain (0110), and what happens
  to `/tree`, `/fork` and resume when the key is missing.
- Compression on its own: zlib with a sync flush per record, not Apple's Compression framework (no flush point; ADR-0138).
- Settings typed (0118), and the `/encrypt` command.
