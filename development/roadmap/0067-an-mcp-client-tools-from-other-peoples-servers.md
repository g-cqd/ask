---
status: in-progress
date: 2026-10-25
---

# 0067 — An MCP client: tools from other people's servers

ADR-0096 holds the decisions. Phases:

1. **Client and stdio transport** (done in this slice): `AskMCP`, tools only, tested against a scripted and a real server.
2. **HTTP transport** (done in the second slice, against a played server; see the ADR's addendum): POST with `application/json` or `text/event-stream` replies, the `Mcp-Session-Id` header when a server sends one,
   a `User-Agent` of ask's own (Cloudflare refused the default one), `DELETE` to end a session (a server may answer `405`), and the
   server's own GET stream, which carries what it says unprompted (ADR-0108).
3. **Integration** (done, ADR-0099): `mcp` in the user's config, a live tool registry, the host and hub, background connection, the sandbox
   rule, a watchdog for a killed ask (ADR-0102), project-level servers behind trust (ADR-0103), `${NAME}` in settings, results as text. A server with more than 16 tools and no `tools` list is searched, not listed (ADR-0100).
4. **Surface** (done): notices, `/mcp`, the destructive-tool approval of ADR-0111, and progress in the transcript (2026-11-02, below).
5. **Still open** (ordered by value):
   - **Approval of what a server does beyond its tools**, such as a tool the server does not mark destructive but that ask learns is (nothing today can learn that).
   - Resources, prompts, OAuth for remote servers, sampling (refused today).

## Decision (2026-10-28, ADR-0123)

MCP is the route for other people's tools in ask.

## Progress in the transcript (done 2026-11-02)

- `ToolContext.progress` (a `ToolProgressReporter`) and `callID`: the loop runs each call in `context.during(call:)`, and a tool tells
  the run how far it has got with `reportProgress(_:)`. The reporter is `Sendable`, as a server's report arrives on its connection's
  reader, not on the loop's task; the screen's run posts it as `ConversationUpdate.toolProgress(id:text:)`.
- A server's call asks for progress (sends a `progressToken`) only when someone shows it: never in `ask -p`.
- `MCPProgressLine`: the share done when the server gives a total (`25% · reading files`), else its words, else its count; the words on
  one line and cut at 48 characters.
- The line is the block's `BlockProgress.note`, shown on the header's right before its time while the call runs, and dropped when it
  ends; the same line again is no change, so a chatty server redraws nothing new.
- Tests: `ToolProgressTests`, `MCPProgressTests`, `ToolProgressNoteTests`; 14 mutants, all killed (one guard found redundant and
  removed). `Scripts/probe-mcp-progress.py` passes through the release binary and the fixture server (whose `echo` takes `slow`).
- Not done: a report's rate is not limited beyond dropping repeats; resources and prompts (phase 5).

## Resources, for the model (done 2026-11-02)

The owner's choice (2026-11-02): both a picker for the person and a tool for the model. This part is the model's; the picker follows.

- apple-docs, the server the owner uses daily, says it has resources: framework trees listed (`apple-docs://framework/<slug>`, JSON), and
  templates for pages (`apple-docs://doc/{+key}`, Markdown), SF Symbols and fonts.
- `AskMCP`: `MCPServerInfo.supportsResources` from the server's capabilities; `listResources()`, `listResourceTemplates()` (each following
  pages) and `readResource(_:)`, whose parts are text or base64 bytes. What has the wrong shape is skipped, as with tools.
- `server_resource` (`MCPResourceTool`, about 60 tokens of definition) is offered while a connected server has resources
  (`MCPResourceShelf`) and withdrawn when the last goes. The server alone lists (the first 100 resources, how many more, every template);
  with a `uri` it reads: text whole, a picture shown as a tool's would be (`MCPResultImages`), other bytes named, not sent. Refused in a
  narrowed session. Not `mcp_…`: such names are refused by Anthropic's subscription endpoint (0144).
- Tests: `MCPResourceTests` (client, 4), `MCPResourceToolTests` (7); 22 mutants, all killed.
- Not verified: the name against the subscription endpoint. (The tool against apple-docs: verified 2026-11-02, below.)
- `resources/subscribe` and the list's change notice: done 2026-11-02, below.

## Resources, for the person (done 2026-11-02)

The owner's choice of syntax: `@server:uri`, Claude Code's. It shares `@` with files and is told apart by the name before the colon.

- `ResourceReferences` (`AskAgentCore`): in the typed line only, each word that starts with `@`, names a connected server that has
  resources and has a URI after the colon is a reference; a sentence's `.,;!?` after it is not part of it. Each is read once, in order,
  when the message is sent, after the turn's servers connect, and attached after the line, as `#t3` is (0186):
  `--- resource server:uri --- … --- end of resource ---`. More than 64 KB is cut, and the model is told to read the rest itself. The
  person is shown only the typed line.
- `MCPHub.attachResources`: text parts joined; bytes named, not sent; an empty read or a failure says so in the text's place.
  `ask -p` attaches too.
- The picker: after `@name:`, where the name looks like a server's (ASCII letters, digits, `-_.`) and what follows is not a line range,
  the screen asks the conversation for `@name`'s rows once (again once stale, as command lists are). That starts servers waiting for
  their first need (0143). A server's rows rank by what follows the colon; a choice puts `@server:uri` in place. A name that is no server
  with resources, or whose list is still coming while nothing follows the colon, keeps the file picker. A URI being typed meanwhile
  says `asking server…`.
- Tests: `ResourceReferencesTests` (6), `MCPHubResourceTests` (3), `ResourcePickerTests` (5); 20 mutants, all killed.
- `resources/subscribe` and the list's change notice: done 2026-11-02, below.
- Not verified: against apple-docs live, in a terminal; the conversation's `resourceRows` guard (a name that is no configured server
  starts nothing) has no test.

## Resources in a message typed during a turn (done 2026-11-02)

- `PromptQueue(prepare:)`: a queued message is prepared when the loop takes it, before the hooks see it (0192); while it is prepared it
  is being recorded, so it cannot be withdrawn. The conversation's queue reads `@server:uri` and then attaches `#t3` and `#i2`, in the
  order a turn's start does; `enqueue` only expands a skill. A message sent back to the input (a failed run) no longer carries `#t3`'s
  text, as it is attached only when taken.
- Tests: `PromptQueueTests` (2 new). The fixture server has a `resources` mode (`note://a`). `Scripts/probe-mcp-steering.py` through the
  release binary: a steering message typed during a slow call names `@fx:note://a`; the next request carries the note after the typed
  line, and the screen shows the line alone (3 checks; the build before fails the second).
- Not verified: against apple-docs live.

## Templates in the picker, and apple-docs live (done 2026-11-02)

- `MCPHub.listedTemplates(of:)`; the `@server:` picker lists a server's templates after its resources, shown whole
  (`@apple-docs:apple-docs://doc/{+key}`, `page · template`). Choosing one writes its fixed part, the URI up to its first `{`
  (`MCPHub.typedPart`), with no space after it and the cursor at its end, and the picker is not offered again on that word, so Enter then
  sends (`PickerRow.leavesOpen`, `PromptEditor.replace(closing:)`). The word picker now inserts a row's `arguments`, which for every
  other row is its label.
- Tests: `MCPHubResourceTests` (1 new), `ResourcePickerTests` (1 new). `Scripts/probe-mcp-apple-docs.py` against the live apple-docs
  through the release binary: its templates listed, the template chosen and finished (`swiftui/view`), the page read and attached after
  the typed line with the screen showing the line alone, and the model's `server_resource` call reading the same page (5 checks).

## Followed resources and changed lists (done 2026-11-02)

The owner's choice: both. apple-docs offers the list's change notice and no subscriptions; the fixture server, in its `resources` mode,
offers both.

- `AskMCP`: `MCPServerInfo.resourcesSubscribable` (`capabilities.resources.subscribe`); `MCPConnection.subscribe(to:)`; the events
  `resourcesChanged` (`notifications/resources/list_changed`) and `resourceUpdated(uri:)` (`notifications/resources/updated`).
- Each resource a message attaches is subscribed to once, after it is read, where its server can (`MCPResourceShelf.follow`); a refused
  subscription changes nothing for the message. When a followed resource changes, the person is told, not the model:
  "@server:uri changed since it was attached; name it again to send what it says now." A change to one never attached says nothing.
- A changed list reaches the screen as `ConversationUpdate.choicesStale(command: "@server")` (`MCPHub.resourceListChanges`): the picker
  asks for it again the next time it opens, showing the old rows meanwhile.
- Tests: `MCPHubResourceTests` (3 new), `ResourcePickerTests` (1 new). `Scripts/probe-mcp-subscribe.py` through the release binary and the
  fixture: the change told, naming the reference, and no request for it (2 checks; the build before fails the first).
- 0067's resource part is done. Left of 0067: approval of what a server does beyond its tools, prompts, OAuth for remote servers,
  sampling.


## OAuth for remote servers (merged 2026-11-05; not verified against a real server)

The owner deferred it on 2026-11-02 ("please record this oauth as a todo for later") and on 2026-11-05 asked for everything off main to be
merged. It is merged with the full gates passing: the build, every test and the quality gate. It is not counted complete: still to do
(task t192) are a discovery and security review, the Client ID Metadata Document (hosting it, and the owner's choice of registration
strategy), and sign-ins against a real protected server in a real browser.

The owner: "oauth should definitely be implemented". His choices: when a server refuses for want of a sign-in, ask asks on the screen
("Open the browser to sign in now?"). The implementation currently identifies itself by dynamic registration, else a client id from the configuration
(`mcp.<server>.oauth.clientId`). A Client ID Metadata Document (the 2025-11-25 specification's first choice) needs a URL the owner
hosts; the owner asked how hosting it would work, and has not selected a registration strategy.

- `AskMCP/OAuth`: `MCPAuthChallenge` (`WWW-Authenticate: Bearer`, RFC 6750 and RFC 9728); `MCPOAuthDiscovery`: the protected resource
  metadata (the challenge's, else the well-known places for the path, then the root), the authorization server's (RFC 8414, then OpenID
  Connect), refusing metadata for another resource, another issuer, no PKCE with S256, and an endpoint a token would reach in the clear;
  a server without the metadata (2025-03-26) is its own authorization server. `MCPOAuthClient`: registration (RFC 7591, a public client),
  the authorization address with PKCE, `state` and the resource indicator (RFC 8707), the code's exchange and the refresh.
- `HTTPMCPTransport` carries an `MCPAuthorization`'s header; a `401` (or a `403` asking for more scope) is renewed once and sent again,
  else answered with "the server needs you to sign in", its challenge kept (`authorizationChallenge`). A token is never sent in the clear
  to another machine, and a plain-http server on the network carries none.
- `MCPServerCredentials` in the credential file (`mcp`, by the server's canonical address): issuer, token endpoint, client id, redirect,
  and the tokens, which are secrets (a keychain keeps them out of the file). `MCPStoredAuthorization` renews through the stored token
  endpoint when a token is due within a minute or refused, one renewal at a time.
- `MCPSignInFlow`: discovery, the client id (configured, kept from an earlier sign-in to the same issuer, or registered now for the port
  the loopback listener took), the browser, the code back on 127.0.0.1 within five minutes, the tokens saved. The host gives such a server
  the state `needsSignIn` (the startup summary and `/mcp` say `/mcp login NAME`), the hub passes its name on (`signInNeeds`), and
  `reconnect` connects that server alone afterwards.
- The screen asks once the turn has ended, as a turn's end clears its questions; a question a turn's end drops is now declined rather
  than left waiting. `/mcp login NAME`. The browser opens through `NSWorkspace`; over SSH or with `ASK_NO_BROWSER`, the address is only shown (no
  program named by the environment is started).
- Tests: `MCPOAuthTests` (8), `HTTPMCPAuthorizationTests` (5), `MCPCredentialStorageTests` (2), `MCPHubSignInTests` (1),
  `MCPStoredAuthorizationTests` (3), `QuestionSectionTests` (1 more). `Scripts/probe-mcp-oauth.py` through the release binary against
  `Tests/AskMCPTests/Fixtures/oauth-server.py` (refuses without a token, its own authorization server checking PKCE and the resource):
  asked, the address shown, signed in, the server ready with its tool (4 checks).
- Not verified: against a real OAuth-protected MCP server; a token's renewal over a long session (unit tests only); the keychain on the
  owner's machine (the probe's keychain is a throwaway one).
