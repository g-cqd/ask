---
status: accepted
date: 2026-10-18
---

# 0018 — Credentials live in one owner-only file, refused when exposed

## Context

`ask login` produces Claude subscription credentials: an access token and a refresh token that can mint
new ones. They have to persist between runs. Borrowing another tool's stored login (pi's file, Claude
Code's Keychain item) was ruled out: ask signs in as itself.

## Options

- **macOS Keychain (login keychain, generic password).** The strongest at rest. Its access list follows the
  creating binary's code signature, so every rebuild of an ad-hoc-signed `ask` prompts the user. The
  data-protection keychain avoids that only with a signing team and entitlements, which ask does not have.
- **A file.** `$XDG_CONFIG_HOME/ask/credentials.json` (absolute XDG paths only), else
  `~/.config/ask/credentials.json`. This is what pi does, made stricter.

## Decision

The file, with these rules, each tested and mutation-checked:
- the directory is created 0700 and the file 0600;
- a save writes a new `O_EXCL` file, fsyncs it, and renames it into place, so a crash leaves the old or new
  credentials and no temporary file;
- a file group or others can read is **refused** (as ssh refuses an exposed key), not trusted;
- a damaged file is an error, never mistaken for being signed out;
- errors report paths, never contents, and the token endpoint's body is never echoed.

## Consequences

- Anyone running as the user can read the tokens, as with ssh keys. The Keychain would not stop that user's
  own processes either, only other users and offline disk access, which FileVault covers.
- When ask ships signed builds, the Keychain becomes the better store. A later ADR supersedes this one then.
- Two processes refreshing at once may race on a rotating refresh token. Not handled yet; owed in roadmap
  0010.
