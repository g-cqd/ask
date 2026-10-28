---
status: accepted
date: 2026-10-26
---

# 0117 — Accounts, models and effort are chosen inside the conversation

## Context

A person signed in to Codex alone could not use ask. `ask` defaulted to Anthropic, which has no sign-in to check at launch, so the screen opened and the first prompt failed with "not signed in"; `ask -p` failed at once.
Probed: `~/.config/ask/credentials.json` held a valid Codex sign-in and a cached catalog (`ask models codex` listed seven models), yet `ask -p "hi"` said `not signed in. Run ask login`.
The only way to Codex was to know `/model codex gpt-6-sol` and type it. `/model` could not list models, `/login` and `/logout` were command-line programs that left the conversation, a Claude or OpenAI API key could not be
stored, there was no way to name an OpenAI-compatible endpoint without editing `providers.json`, and the effort a model thinks at was a launch flag only.

## Decision

1. **A provider that nothing names is one that can answer** (`AutoProvider`): Claude if signed in (or its key is in the environment), then Codex, then Antigravity, else Apple's on-device model (ADR-0116). A flag, the
   configuration or `providers.json`'s default still wins. The choice is announced once.
2. **`/model`, `/thinking`, `/login`, `/logout` are lists** (`SlashCommand.takesChoices`). Typing the command and a space opens the picker that commands and files already use, with its keys (Up, Down, Esc) and its click
   (ADR-0070); typing narrows it, words in any order; **Enter or a click runs the command with the row, at once**. `/model` lists every model of every account signed in to and every configured provider and connection,
   each asked at once with eight seconds' patience and a fresh cache answering without a network; one that fails is named at the end of the list. After a model is chosen the effort list for it opens by itself
   (`ThinkingOptions`: the levels its catalog entry names, the server's default marked, `unverified` when the entry lists none); Esc keeps the default. Choosing a model whose new provider cannot take the level that
   was set puts it back to the default and says so, rather than refusing the model.
3. **A command can ask the person a line** (`ConversationUpdate.askInput`, `PendingInput`): shown in the status line, typed into a buffer that is not the draft, hidden as dots and a count when it is a secret, sent by
   Enter, cancelled by Esc, and cancelled with the command by Ctrl+C. A secret never reaches the transcript, the scrollback or a session file.
4. **Login is one implementation over two surfaces** (`AccountLogin` over `SignInInteraction`): `ask login …` on the terminal and `/login …` on the screen are the same code. Each provider signs in by its account
   (Claude by browser and pasted code; Codex by browser with a pasted address as the fallback, or by device code; Antigravity; Spettro and Mistral Vibe by browser) **or by an API key** where there is one: `claude api-key`,
   `codex api-key` (OpenAI's key, stored as `openai`, which is what the Codex API is), any key preset by name, and `custom NAME URL` for any OpenAI-compatible server (the endpoint goes in `providers.json` without a key;
   the key is stored with the other credentials). One account has one way in: a Claude key replaces the subscription in the same write and the subscription's sign-in forgets the key. A named connection stays an account.
5. **Logout is the same**: `/logout` lists what is stored (and, as unremovable, what only the environment holds), `/logout all` forgets everything, and none of it leaves the conversation; the run follows what is left.
6. **The words are shared** (`LoginRequest`), so `ask login` and `/login` cannot disagree.

Not changed: the credential file's format and locking, named connections, and `ask login`'s defaults (`ask login` still means Claude's account).

## Evidence

| Claim | Probe | Result |
|---|---|---|
| Before: signed in to Codex only, `ask -p "hi"` fails | the base binary, this machine | `not signed in. Run ask login, or set ANTHROPIC_API_KEY` |
| After: it uses Codex | `ask -p "Say OK only."` | `No provider chosen; using codex…`, answered `OK` |
| `/model` lists, narrows, runs at once, then offers the effort list, whose choice is in force | `Scripts/probe-accounts.py` A (real binary, PTY, a copy of the real Codex credentials) | 8 checks pass |
| `/login claude api-key` asks in the status line, shows dots, stores the key, and the key is on no screen and in no session file; ask keeps running and opens the model list for the new account | probe B | 8 checks pass |
| Esc cancels (not an error); `/logout` lists and signs out in the conversation | probe C | 5 checks pass |
| A wrong `/login` says so and stays | probe D | 2 checks pass |
| CLI: `login claude --api-key`, `codex --api-key`, `custom NAME URL` (with and without a key), `groq`, a bogus name, `logout` twice | `ask` against a private `XDG_CONFIG_HOME` | stored under `anthropic`, `openai`, `my-llm`; `providers.json` holds no key and is 0600; bogus refused; second logout says nothing is signed in |
| The state machine: list asked once and again when aged, narrowing, Enter and click run the command, Esc, a row that completes, the secret never shown | `ChoicePickerControllerTests` (9), `ChoicePickerClickTests` (2), `InputQuestionControllerTests` (8) | Pass |
| The words, the key check, accounts and sign-out, `providers.json`, the effort rules | `LoginRequestTests`, `APIKeyTests`, `CredentialFileAccountsTests`, `ProviderFileTests`, `ThinkingOptionsTests` | Pass |
| Codex advertises `ultra` | `ThinkingControlTests` already records that live inference **refuses** it; I added it to `ThinkingLevel`, the test failed, and I took it out. The list does not offer it | Kept out |

Two of my own mistakes, for the record: the probe raced the screen (a key typed before the question was drawn went to the editor, so `until("API key")` matched the previous question's text; the probe now waits
for `Enter sends`), and the first version of the stored-key read for custom endpoints made a damaged credential file block a keyless local server, which `ProviderPresetTests` caught.

## Consequences

- Not probed live: the browser sign-ins (Claude, Codex, Antigravity, Spettro, Mistral Vibe) from the screen. They are the same functions the command line ran, with `show` and `paste` rebound to a notice and a question;
  their transport and credential tests are unchanged. The pasted-address fallback needs a browser to try.
- A `custom` endpoint's `/models` list is asked with the stored key; a server that has none is listed without.
- The Codex "API key" is OpenAI's, reached through the `openai` preset (chat completions); whether it should speak Responses is open.
