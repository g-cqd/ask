---
status: accepted
date: 2026-11-01
---

# 0138 — An appendable file that can be compressed, encrypted, or both

## Context

Wish (2026-11-01, roadmap 0182): session files compressed and, separately, encrypted, with a password whose key lives in the
keychain; global or per workspace; the password remembered or asked at every start, or a question at each start; `/encrypt on|off`.
The task list (0179) and the ideas (0180) need a store too, "never a markdown file, only json and/or even protobuf", which may be
compressed or encrypted the same way. One container serves all three.

What session files already guarantee, and the container must keep (ADR-0013, ADR-0017, ADR-0024):
- one append per change, flushed per `Durability` (`.barrier`) before the change counts;
- opening never writes; a torn last record is dropped; the first change after a damaged open writes a fresh file and keeps the
  original as `<name>.damaged`;
- one writer, under `SessionLock`; images kept beside the file (`SessionImageStore`).

Measured on this machine (M3, release, 2026-11-01, `/tmp/probe.swift`):
- zlib raw deflate, one stream with `Z_SYNC_FLUSH` after each record: a prefix cut at any flush point inflates to exactly the records
  before it. Apple's Compression framework has no sync flush, so a record could not be read until the stream ends.
- PBKDF2-HMAC-SHA256 (CommonCrypto), 600,000 iterations: 79 ms.
- 1,000 seals of 4 KiB: AES-GCM 1.3 ms, ChaChaPoly 7.1 ms (CryptoKit; AES has hardware support).

## The owner's choices (2026-11-01)

- **Key derivation: Argon2id**, not PBKDF2, from aemi's `AemiArgon2` (aemi ADR 0024): NEON with SHA3, data-independent timing,
  red-first, mutation-tested, attacked with a timing test. Parameters: 19 MiB, 2 passes, 4 lanes on 4 threads (RFC 9106's second
  recommendation is 64 MiB; OWASP's minimum is 19 MiB), about 4 ms here. It runs only when a password is typed, never at start with
  "remember"; its memory is wiped and released at once. Parameters read from `keys.json` are bounded before use (at most 256 MiB, 10
  passes, 16 lanes), so a tampered file cannot exhaust memory.
- **The cipher stays symmetric, with 256-bit keys: AES-256-GCM.** Asked for algorithms that quantum computing does not weaken: quantum
  attacks halve a symmetric key's strength at most (Grover), so a 256-bit key keeps 128 bits, which Apple and NIST call quantum-secure;
  what quantum computers break is public-key cryptography, and this design has none. If a key is ever sent to another device, that
  exchange uses CryptoKit's hybrid post-quantum X-Wing (ML-KEM-768 with X25519). Nothing is known to be weakened by AI-assisted analysis.
- **A recovery key**: shown once when encryption is turned on, 256 random bits written as words of base32; it wraps a second copy of
  the user key in `keys.json`, so a forgotten password loses nothing if the recovery key was kept.
- **Default: ask at first start** whether to encrypt sessions, and whether to remember the password.
- **A workspace may turn encryption and compression off** as well as on: the workspace's setting wins either way.

## Decision

### 1. A plain file stays plain JSONL

With neither setting on, a session file is today's JSONL, byte for byte: people read and grep it (0122). The container exists only
when compression or encryption is on, and a reader tells them apart by the first bytes (a JSONL file starts with `{`).

### 2. The container

```
header:  magic "ASKF" · version u8 · flags u8 (compressed, encrypted) · payload u8 (json, protobuf)
         file id (16 random bytes) · envelope length u16 · envelope (phase 2: the wrapped data key) · CRC-32 of the header
frames:  length u32 LE · kind u8 · CRC-32 of length and kind · body
         kind 1 record
```

- **Compressed only:** each body is the record's deflate bytes up to its sync flush, followed by a CRC-32 of the plain record.
- **Encrypted:** each body is `nonce (12) · ciphertext · tag (16)`. Additional data is the header's SHA-256 and the frame's index, so
  frames cannot be moved between files or reordered. The nonce is random per frame, not a counter. A counter would repeat after a torn
  tail was rewritten under the same key; the cost of a random nonce is 12 bytes per record.
- **Both:** compress, then encrypt.
- **Overhead:** 37 bytes per encrypted record (frame header 9, nonce 12, tag 16), 13 per compressed one (frame header 9, CRC 4).
- **Compression level:** zlib's default (6). Measured on 128 real session files: text records frame 2.2 times smaller (level 1: 2.0),
  base64 records 1.4; about 57 µs per record on average, the largest included.

### 3. Appending and recovery

- **Appending** writes one frame and flushes, as today.
- **Reopening** starts a new deflate stream, and needs no marker: each record ends on a sync flush's block boundary, and a new stream
  only refers to its own bytes, so the reader's stream decodes it as it is (a planned segment frame was dropped when a mutation removing
  it changed nothing, 2026-11-01).
- **A frame header has its own CRC-32**, so a changed length is damage, never mistaken for a tear: a crash only cuts a file short.
- **A last frame that is short, fails its CRC or fails authentication is a torn tail**, dropped as today.
- **A bad frame before the last one makes the file damaged.** The rewrite writes a fresh file under a new data key, keeping the original
  as `<name>.damaged`.
- **Truncation:** a frame cut off whole at the end cannot be told from a torn tail. That is the same guarantee as JSONL today, and it is
  stated as such.

### 4. Keys

- **A user key:** 256 random bits, made the first time encryption is turned on.
- **A data key per file**, also random, wrapped in the header by the user key (AES-GCM). Changing the password rewraps the user key only,
  never a session file.
- **The password wraps the user key.** It is derived with Argon2id and a 16-byte salt. The wrapped copy
  is kept under ask's state directory (`keys.json`: salt, iterations, KDF id, wrapped user key). The wrap's tag checks the password, so
  no hash of the password is stored anywhere.
- **"Remember":** the user key itself goes into the login keychain, readable when unlocked, on this device only (as in 0110). Nothing is
  derived at start, and the keychain is read only when an encrypted file is first opened, never on the cold-start path.
- **"Every start":** the password is asked the first time an encrypted file is opened or created; the derivation's few milliseconds
  are spent while a person waits on the prompt anyway.
- **The KDF and its parameters are in `keys.json`,** so they can change later without touching session files.

### 5. Settings and commands

- `sessions.compression`: `false` or `true`. `sessions.encryption`: `off`, `on` or `ask`, where `ask` puts a question at the start of
  each new session. `sessions.password`: `remember` or `everyStart`.
- All three are typed settings (0118). A workspace's file overrides the user's either way (owner, 2026-11-01).
- `/encrypt on|off` (with `enable`/`disable`, `true`/`false`, `1`/`0`) rewrites the current session file by the same atomic path as a
  damaged rewrite, leaving no plaintext copy behind. `ask key password` changes the password, and `ask key forget` removes the
  keychain's copy.

### 6. Without the key

- Session lists (`/sessions`, `/tree`, resume) show an encrypted session as `locked`, with its date only. The title is inside the file.
- Opening one, forking it, or resuming it asks for the password once per process.
- A wrong password three times leaves the session closed. Nothing else is written.
- Images of an encrypted session are encrypted too, one frame per image, under the session's data key.

### 7. The task and idea store (0179, 0180)

- The same container, always used (no plain mode), payload `json` now and `protobuf` once AemiProtobuf is ready (0122).
- Each frame is one change (add, edit, state, link) to the list, and on open the list is rebuilt from the changes, as a session is.
- Per session, it lives beside the session file and shares its data key. Per workspace, it lives under ask's state directory, keyed by
  the workspace's path.

## Options not taken

- **PBKDF2:** proposed first, for being in CommonCrypto; the owner chose Argon2id.
- **ChaChaPoly:** as safe, and fine without hardware AES (0135's Linux and Windows). It is 5.6 times slower here, though both cost
  microseconds per record. The cipher id lives in the version byte, so it can be added later.
- **Apple's Compression (LZFSE, zstd-like):** it has no flush point, so each record would be its own stream. Small records then barely
  compress.
- **Encrypting the whole file at close:** a crash would leave the session in plaintext, or lose it.
- **Storing a hash of the password in the keychain** (the wish's wording): the wrap's tag already checks a password. A stored hash would
  only give an attacker something to guess against.

## Consequences

- An encrypted session cannot be read with `cat` or `jq`. `ask session cat <id>` prints its JSONL after asking the password.
- A forgotten password and a lost recovery key lose every encrypted session; ask says so when it shows the recovery key.
- Compression with encryption reveals each record's compressed length. That only matters if someone can both inject text into a session
  and watch the file's size; it is noted here and not mitigated.
- zlib is a new system library linked into AskAgentCore. It ships with macOS, but 0135's other platforms would need it.
