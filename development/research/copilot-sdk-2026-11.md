# Copilot, the Local harness's end, and the Copilot SDK: what it means for ask

Report for the owner, 2026-11-12 (note n69). Research only: nothing in ask has changed yet. Sources are listed at the end; what is
announced is kept apart from what I infer.

## 1. In one paragraph

VS Code is retiring its original Copilot agent, the **Local harness**, in **February 2027** (announced in VS Code 1.146). Its
replacement, the **Copilot harness**, is the agent runtime of the Copilot CLI, which programs drive through the **Copilot SDK**
(being renamed the **Microsoft Copilot SDK**). ask's Copilot account today does what the Local harness did: it signs in as VS Code,
copies VS Code's and Copilot Chat's version numbers into its headers, and calls Copilot's model API directly. Nothing announced says
that API path closes in February. But its main legitimate user leaves, so the path ask copies becomes one nobody official uses any
more. The SDK is the supported way for a third-party program to use a Copilot subscription. It is a whole agent runtime, though, not a
model API, and that is the decision for ask: how much of ask's own loop to hand to it.

## 2. The words, explained

| Term | What it is |
|---|---|
| **Harness** | Everything around the model: the prompt, the tools, the loop that calls the model and runs its tool calls, approvals, compaction. ask is a harness. |
| **Local harness** | VS Code's original Copilot agent, run inside VS Code's extension host. Deprecated in VS Code 1.146; removed in February 2027. It is "functionally frozen" until then. |
| **Copilot harness** | The agent runtime of the Copilot CLI (recently ported to Rust), now shared by VS Code, the CLI, the GitHub Copilot app and Microsoft products. Default for new VS Code sessions since 1.143. |
| **Agent Host** | VS Code's process that hosts harness sessions outside the editor window, so they keep running and can move between surfaces. |
| **Copilot SDK** | Libraries (TypeScript, Python, Go, .NET, Rust, Java) that drive the Copilot runtime over JSON-RPC. They are thin: the runtime does the work. |
| **Microsoft Copilot SDK** | The same SDK under a new name and organisation (announced 2026-10-28). Package names change in phases; "no immediate changes are required". |
| **CAPI** | Copilot's model API (`api.githubcopilot.com`), what ask calls today. |
| **BYOK** | Bring your own key: the runtime calls OpenAI, Anthropic or Foundry with your key instead of your Copilot subscription. |

## 3. What ask does today

The Copilot account (`Sources/AskAI/Copilot`, about 900 lines, and `Sources/ask/*Copilot*`):

- **Sign-in:** GitHub's device flow with VS Code's OAuth client ID (`01ab8ac9400c4e429b23`).
- **Token:** `api.github.com/copilot_internal/v2/token`, an internal endpoint, exchanges the GitHub token for a Copilot one.
- **Identity:** every request names `editor-version: vscode/1.144.0`, `editor-plugin-version: copilot-chat/0.72.0`,
  `copilot-integration-id: vscode-chat`, and a machine ID.
  - To stay current, `VSCodeBuild` reads the newest official VS Code archive and its bundled `extensions/copilot/package.json`
    (roadmap 0193).
- **Models:** the catalogue, then `/responses`, `/v1/messages` or `/chat/completions`, encoded by ask's own provider encoders. ask's
  loop, tools, sandbox, compaction, sessions and screen are used as with any provider.

In short: ask is a harness that presents itself to Copilot as VS Code's Local harness.

## 4. How February 2027 affects ask

| What | Announced? | Effect on ask | Likelihood |
|---|---|---|---|
| The Local harness leaves VS Code | Yes, February 2027 | None directly: ask does not run inside VS Code. | Certain |
| VS Code's own model calls move to the runtime, which names itself through the SDK's client info (`vscode-agent-host`, `vscode/<version>`) | Yes (SDK docs on client info) | The identity ask copies (`vscode-chat` from the extension host) stops being VS Code's live traffic. ask then looks less like VS Code and more like an outlier. | High |
| GitHub restricts or changes CAPI for the `vscode-chat` integration, or the token endpoint, once nothing official uses it | No | The Copilot account stops working, with an error or quietly (different models, limits). It can come without notice: these are internal endpoints. | Unknown; it rises after February |
| VS Code stops bundling Copilot Chat as `extensions/copilot`, or renames it | No | `VSCodeBuild` fails to read the versions; ask falls back to the last known ones (1.144.0 / 0.72.0), which age. | Medium over 2027 |
| Terms of use | — | Presenting a third-party program as VS Code is already a grey area. The SDK, with ask named in its client info, is the sanctioned route; the copied identity is not. | Standing |

Not affected: the Anthropic, Codex, Antigravity and API-key providers, and everything that is not Copilot.

## 5. What the SDK offers ask

- **Architecture:** the SDK speaks `Content-Length`-framed JSON-RPC to the runtime: the same framing as LSP and MCP over stdio, which
  ask already speaks. There is no Swift SDK, so ask would implement the client itself, as it did for MCP.
- **Transports:**
  - the runtime as a child process over stdio or TCP (the established path);
  - an external runtime at a URL;
  - **in process**, loading the native runtime library through a fixed C ABI (experimental), which Swift can call directly.
- **Runtime binary:** the Copilot CLI (`@github/copilot` 1.0.109 today). Its licence allows redistributing unmodified copies inside an
  application with "material functionality beyond the Software itself", with the licence included. ask qualifies. Or ask can use the
  person's installed CLI (`COPILOT_CLI_PATH`).
- **Sign-in:**
  - the `copilot` CLI's own login (kept in the keychain);
  - tokens from a GitHub OAuth app (ask would need its own registered app);
  - environment variables;
  - server-to-server tokens;
  - BYOK.

  No more borrowing VS Code's client ID.
- **Billing:** the CLI's model: each prompt counts against the subscription's premium requests. Per-call `cost` multipliers and quota
  come back as events and RPCs.
- **What ask can control:**
  - **Tools:** its own tools, declared with JSON Schema and run by ask (`tools`); the runtime's built-in tools filtered out
    (`availableTools` / `excludedTools`); and tools replaced mid-session (experimental).
  - **System prompt:** appended to, edited section by section, or replaced whole (`systemMessage` modes `append`, `customize`,
    `replace`).
  - **Approvals and hooks:** a callback for each permission request; hooks before and after a tool use, on prompt submission and on
    session lifecycle.
  - **Session control:** steering and queueing (`send` modes `immediate` and `enqueue`), abort, the model switched mid-session,
    reasoning effort, the model list with capabilities and billing, and usage and context-window events.
- **What the runtime owns:** the loop itself, its own session store (`~/.copilot`, or a chosen `baseDirectory`), its own compaction
  ("infinite sessions"), subagents and plans.

## 6. The ways ask can integrate

**A. Copilot as a second harness inside ask.** ask starts an SDK session and shows its events in a lane, as `/thread` does. Copilot's
runtime runs its own tools, and its permission requests come to ask's approval prompt.
- For: little to build beyond the client; Copilot behaves exactly as in VS Code and the CLI.
- Against: ask's tools, sandbox, compaction and session file do not apply; it is Copilot's agent inside ask's screen.

**B. Copilot's runtime as the loop, with ask's tools and prompt.** The built-in tools are filtered out, so only ask's tools exist
(bash under ask's sandbox, read, write, edit, the task list...). The system message is replaced with ask's, and the events map to ask's
transcript.
- For: a sanctioned Copilot path that keeps ask's tools, sandbox, approvals and screen.
- Against: two loops in ask, its own and Copilot's. Copilot's runtime owns the history and the compaction, so ask's session file,
  `/rewind`, light compaction and hooks would be a mirror for Copilot sessions, not the source.

**C. Keep today's path, and prepare.** Nothing changes now. ask detects the day it breaks and says so plainly, and one of A or B is
ready before then.
- For: the best Copilot experience in ask until it breaks.
- Against: it can break without warning, and the terms question stands.

The three can coexist: C now, A as the first SDK step (it needs only the client), and B when it is proven.

## 7. A staged plan

1. **Stage 0, now (small):**
   - a probe that runs today's Copilot path weekly and records any change (status, headers, model list);
   - a clear message when the Copilot account fails;
   - a roadmap entry for this topic.
2. **Stage 1, the client:**
   - a Swift JSON-RPC client for the runtime over stdio, against the person's installed `copilot` CLI;
   - `server.connect` with ask's client info;
   - the model list, a session, one prompt and its streamed events, abort;
   - probed live.
3. **Stage 2, option A:** a Copilot harness lane in ask, with permission requests in ask's approval prompt, usage in the status line,
   and resume through the runtime's session IDs.
4. **Stage 3, option B:** a `copilot-sdk` provider in which the runtime's loop calls ask's tools, with `systemMessage: replace` and
   built-in tools filtered out. It is measured against today's path on the same tasks (speed, tokens, quality), and the session mirror
   is designed (an ADR).
5. **Stage 4, optional:** the in-process C ABI transport (no child process), once it is no longer experimental, measured against ask's
   cold-start and memory budgets.
6. **Before February 2027:** decide whether the old path stays as an option, becomes off by default, or goes.

## 8. Decisions for you

1. Which integration you want: **A**, **B**, or both in stages as above.
2. The runtime binary: require the person's installed Copilot CLI, or bundle it (allowed by its licence)?
3. Sign-in: the CLI's own login, or ask's own GitHub OAuth app? The app would have to be registered under your account.
4. Today's VS Code identity path: keep until it breaks, make it off by default from February 2027, or remove it once the SDK path
   works?
5. Accounts: on this Mac `gh` holds your work account. Which GitHub account should ask's Copilot sign-in use?

## Sources

- VS Code 1.146 release notes, "Copilot harness and deprecation of the Local harness":
  https://code.visualstudio.com/updates/v1_146
- VS Code 1.145 release notes (harness picker, transition guide): https://code.visualstudio.com/updates/v1_145
- Local-to-Copilot harness transition guide: https://code.visualstudio.com/docs/agents/run/move-to-copilot
- Agent Host architecture: https://code.visualstudio.com/blogs/2026/08/26/agent-host-architecture
- GitHub changelog, 2026-10-28, "GitHub Copilot SDK is becoming Microsoft Copilot SDK":
  https://github.blog/changelog/2026-10-28-github-copilot-sdk-is-becoming-microsoft-copilot-sdk
- Microsoft blog, 2026-10-28, "Introducing the Microsoft Copilot harness":
  https://blogs.microsoft.com/blog/2026/10/28/introducing-the-microsoft-copilot-harness-unlocking-the-potential-of-truly-multi-model-agentic-work/
- The SDK repository and its docs (README, agent loop, authentication, BYOK, in-process runtime, compatibility, client info, usage and
  billing): https://github.com/github/copilot-sdk
- Copilot CLI licence (`@github/copilot` 1.0.109, LICENSE.md)
- microsoft/vscode#347616 (users on the removal) and #340335 (BYOK in the Agent Host harness)
- ask: `Sources/AskAI/Copilot/*`, roadmap 0193

## Recorded (2026-11-12): the pinned runtime's sign-in and account calls

The Copilot CLI 1.0.109 (`@github/copilot-darwin-arm64`, tarball sha256 `d00563d5…c37a`) run once through a local recording proxy,
its home and its keychain throwaway (deleted after; the owner's login keychain left as it was). Tokens, cookies and machine IDs are
not kept.

- Sign-in: the CLI's own GitHub app, client `Ov23ctDVkRmgkPke0Mmm`, by a browser flow with a loopback callback (default on a desktop)
  or a device code (`--device-code`); scopes `read:user read:org repo gist codespace …`. It accepts `COPILOT_GITHUB_TOKEN`, `GH_TOKEN`
  or `GITHUB_TOKEN`: fine-grained tokens with "Copilot Requests", the CLI app's tokens and `gh`'s; not classic `ghp_` tokens.
- No token exchange: the GitHub token goes straight to Copilot's API. No `copilot_internal/v2/token` call was seen.
- The API's host follows the plan: `api.individual.githubcopilot.com` or `api.business.githubcopilot.com`.
- Its headers: `copilot-integration-id: copilot-developer-cli`, `copilot-harness-id: copilot-sdk`, `editor-version: copilot/1.0.109`,
  `user-agent: copilot/1.0.109 (darwin <node version>) term/<terminal>`, `openai-intent: conversation-agent`, `x-initiator: user`,
  `x-interaction-id` and `x-client-machine-id` (UUIDs), `x-github-api-version: 2026-09-21`.
- Behind the proxy the runtime refuses an organisation's account on its own side: a configured trust root (`SSL_CERT_FILE`,
  `NODE_EXTRA_CA_CERTS`) means, in its words, "the organization memberships backing this pin could in principle be intercepted".
- Without the proxy GitHub refused both the owner's work account and g-cqd: "Access denied by policy settings" (the Copilot CLI
  policy, separate from `gh`'s), so no model call was recorded. VS Code's Agent Host identity (the SDK's client info,
  `vscode/<version>`) was not observed either.
