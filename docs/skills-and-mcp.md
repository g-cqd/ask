# Skills and MCP servers

## Skills

A skill is a directory with a `SKILL.md`: instructions the model loads when a task matches them. ask reads the skills of every harness you
use, so the ones you wrote for Claude Code, Codex, pi, opencode, Mistral Vibe or Copilot work here too, along with `~/.config/ask/skills`,
`.agents/skills` and `.ask/skills`.

- `ask skills` lists what was found, and anything odd about a skill.
- The model sees a list of up to 32 skills; with more than 16 to offer, it gets a search instead and finds them by name or topic.
- `/skill:NAME request` asks for one yourself, and `/` lists them.
- A skill only gives instructions; it grants no permission.
- **A project's skills load only once you trust them**: run `ask trust --skills` at a terminal. Trust covers
  the `SKILL.md` file: when it changes, it needs trusting again. The files beside it (scripts, references) are not covered; the model reads
  or runs them only as it would any file in the repository, under the sandbox and your approvals.

`skills` in [configuration](configuration.md#skills) turns them off, changes the count, or limits where ask looks.

## MCP servers

An MCP server offers the model more tools: a program ask starts, or a service at a URL. Name it under `mcp` in your own
`~/.config/ask/config.json`:

```json5
{
  mcp: {
    github: { command: "github-mcp-server", args: ["stdio"], env: { GITHUB_TOKEN: "${GITHUB_TOKEN}" } },
    docs: { url: "https://example.com/mcp", headers: { Authorization: "Bearer ${DOCS_TOKEN}" } },
  },
}
```

`${NAME}` takes the value from your environment, so a token need not be written in the file.

- Its tools reach the model as `mcp__github__<tool>`. The servers connect when you send your first message, not when ask starts, so an idle ask holds none of them; that message
  waits for them, ten seconds at most, and a slower one joins when it is ready. One block then says how many connected and why any failed;
  `/mcp` shows each server, how many tools it offers, and how to choose them.
- A server runs **outside** ask's sandbox, so naming it is your consent. A project's file can name one only once you have trusted it
  (`ask trust`). It can also turn one of yours off, or narrow its tools, for that project alone: `{"mcp": {"xcode": {"enabled": false}}}`
  changes your `xcode` server without replacing it ([Configuration](configuration.md#mcp)).
- A server with many tools (more than 16) is offered through a search, to keep the model's prompt short. `tools: [...]` keeps only the ones
  you name, and `mode` and `maxDirectTools` change how they are offered ([Configuration](configuration.md#mcp)).
- A tool the server marks as destructive is asked about before its first use in a session.
