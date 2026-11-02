---
status: done
blocked-by: []
date: 2026-11-02
---

# 0193 — The Copilot connection names the newest official VS Code and its Copilot Chat

Owner (2026-11-02): "always pick the latest version of vscode and the copilot extension and match their sent user agent at all time, we
should maybe cache the information for 1hour or something"; then "i'd prefer you use the official vscode build information and same
for the chat integration".

## What was found

- ask sent `GitHubCopilotChat/0.44.0`, `editor-version: vscode/1.115.0` and `editor-plugin-version: copilot-chat/0.44.0`. The newest
  stable VS Code is 1.144.0.
- Since VS Code 1.121 Copilot Chat ships inside VS Code (`extensions/copilot`). The marketplace's copy stopped at 0.48.1, so it cannot
  name the current one. In 1.144.0 it is 0.72.0.
- The header formats are unchanged: `GitHubCopilotChat/<chat>`, `vscode/<vscode>`, `copilot-chat/<chat>` (`envService.ts`,
  `baseFetchFetcher.ts`).
- Chat requests over HTTP now go through `networkRequest`, which sends `X-GitHub-Api-Version: 2026-01-09`. `2025-05-01` is now only
  its WebSocket path's. The token exchange keeps `2025-04-01`.
- The shipped build's `extension.js` sets the integration ID to `vscode-chat` for production builds (the source says `code-oss`, which
  the production build replaces), and contains `2026-01-09`. Both checked in the 1.144.0 archive.

## Done (2026-11-02)

- `VSCodeBuild` reads the newest official build:
  - VS Code's update service names the archive (only `https://vscode.download.prss.microsoft.com`) and its commit;
  - HTTP ranges read the archive's end, its directory, `product.json` and `extensions/copilot/package.json`: about 800 KB of a 350 MB
    zip, in five requests;
  - `product.json`'s commit and version must match the release's, and the package must be `copilot-chat`.
- `ZipDirectory` and `Inflate` read stored or deflated files (the system's Compression framework); no zip64, sizes bounded.
- `CopilotVersions` keeps the result for an hour in `copilot-vscode-version.json`, beside the credentials. A failed check keeps the last
  versions read (or `CopilotClientVersion.known`, 1.144.0 and 0.72.0) and is tried again after five minutes. Only plain versions are
  used, so nothing else can reach a header.
- Sign-in, the token exchange, the catalogue and every chat request name the versions; chat sends `2026-01-09`.
- Tests: CopilotVersionsTests, CopilotVersionsUseTests, ZipDirectoryTests. Every guard's mutant is killed (two runs, 33 mutants).
- Live: the check read 1.144.0 and 0.72.0 from the official build, and a chat request to `claude-haiku-5.5` answered.

## Not done

- The first Copilot request in an hour waits for the check (about half a second when it was measured).
- The other headers VS Code's `@vscode/copilot-api` client adds are not compared; they live in that npm package, not in VS Code's
  source.
