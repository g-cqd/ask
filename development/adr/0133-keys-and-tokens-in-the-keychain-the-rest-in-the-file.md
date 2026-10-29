---
status: accepted
date: 2026-10-29
---

# 0133 — Keys and tokens in the Keychain, the rest in the file

## Context

Roadmap 0110: the owner wants keys kept in the system keychain by default, with the file still possible as a setting. Every key and token
goes through `CredentialFile`, one 0600 JSON document changed in locked transactions. The investigation (0110) measured the legacy
keychain: an item written by one ad-hoc build prompts after every rebuild; builds signed with the personal Apple Development identity read
each other's items with no prompt; the data-protection keychain needs a provisioning profile. The owner: the Keychain holds the keys, and
nothing more than that.

## Decision

1. **Only secrets go to the Keychain.** Access and refresh tokens, Antigravity's client secret, Copilot's GitHub token and API keys.
   Emails, expiry dates, account and project IDs stay in the file, readable by `ask` commands that need no secret. The file keeps the
   marker `ask:keychain` where a secret was, so it still says what is stored.
2. **One generic password item per record** (service `ask`, account the file's path, `#`, the record: `claude`, `codex`, `agy`,
   `copilot`, `keys.<provider>`), holding the record's secret fields as JSON. Named connections' files have their own items by path.
3. **The file's transaction stays the unit.** A write stores each record's secrets, reads each back and compares, then renames the file
   with markers into place, then removes items no longer needed. A Keychain that refuses throws before the file is touched, so a failure
   leaves everything as it was; a crash between the two leaves items the file does not mark yet, harmless. A marked record whose item is
   gone is an error that says to sign in again, never a silent sign-out.
4. **`credentials`: `"auto"` (default), `"keychain"`, `"file"`**, in the person's own config only (a project's file is refused: it would
   choose where the person's keys go). `auto` is the Keychain for a build signed with an identity (`SecCodeCopySigningInformation`: not
   ad hoc, has certificates) and the file for an ad-hoc one. An unsigned build under `auto` never moves anything, and uses the Keychain
   for a file that already marks its secrets there, so a test build or a gate run never pulls secrets back into the file.
5. **Moving follows the setting.** When the configuration is loaded and the choice differs from the process's last, `CredentialPlacement`
   settles ask's own file and every named connection's: secrets into the Keychain, or back into the file and the items removed. A file
   that cannot be settled stays as it was, with a notice.
6. **Tests never touch the login keychain.** `KeychainSecretStore` takes a keychain file; `ASK_KEYCHAIN_PATH` (absolute only) points the
   real binary at a throwaway one for end-to-end runs. The file's logic is tested against a store in memory.

## Consequences

- Builds must be signed with the personal identity for `auto` to use the Keychain: a signing step after the build and before `/reload`
  switches (still owed, 0110). `codesign` asks once for the identity's key unless it is allowed to use it.
- On a locked keychain (SSH) a save fails with a message that says to unlock it or choose `"file"`; reading needs no unlock prompt for the
  signed binary's own items once the keychain is unlocked.
- The deprecated `SecKeychainOpen` is used only for a given keychain file, declared with `@_silgen_name`; production uses the default
  search list.
