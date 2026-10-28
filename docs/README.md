# Using ask

ask is a terminal coding agent for macOS. What it gives you:

- **Many accounts, one screen.** Claude, ChatGPT (Codex), Antigravity, API keys for many services, any OpenAI-compatible server, and Apple's
  on-device model. `/model` switches between them mid-conversation.
- **A sandbox by default.** Commands and file tools can't touch ask's own files or your secret stores; you can narrow writes and the network
  further.
- **Nothing lost.** Every conversation is saved as it happens; go back to an earlier prompt with `/tree`, or branch with `/fork`.
- **Your skills and MCP servers.** Skills written for other harnesses work as they are; MCP servers add tools.
- **No setup needed.** `ask config` shows every setting, its default, and where it came from.
- **Fast and light, by number.** A 50 ms cold start, 15 MiB idle, 4 ms from a key press to the screen: `ask --budgets` prints these budgets,
  and the release build is measured against them.

## The guide

- [Getting started](getting-started.md): install, sign in, first run, one prompt from the shell.
- [The screen and its keys](screen.md): writing prompts, stopping a turn, folding, background jobs, the commands.
- [Sessions](sessions.md): continuing, going back to an earlier prompt, forking, compaction.
- [Configuration](configuration.md): recipes first, then every setting with its default.
- [Providers and accounts](providers.md): signing in, choosing a model, several accounts, your own server.
- [The sandbox](sandbox.md): what the model can reach, and how to change it.
- [Skills and MCP servers](skills-and-mcp.md): giving the model instructions and more tools.

This folder is for people using ask. How ask is built (decisions, plans, the working log) lives in [`development/`](../development/), and
none of it is needed to use ask.
