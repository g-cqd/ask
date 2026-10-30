# The sandbox

The model's tools run in a sandbox, on by default. The read, write and edit tools check a policy, and every command runs under macOS's
sandbox with the same policy. It costs a few milliseconds per command.

## What it protects

By default the model can read and write anywhere you can, and reach the network, **except**:

- ask's own files (`~/.config/ask`, its sessions and credentials);
- `~/.aws`, `~/.gnupg`, your Keychains, `~/.netrc` and ssh private keys.

When something is refused, the model is told so, plainly, so it does not look for a way round it. `ask config` shows the sandbox in force.

## Making it stricter

In any configuration file (see [Configuration](configuration.md#sandbox)):

```json5
{
  sandbox: {
    write: "workspace",      // only the project and temporary directories
    read: "workspace",       // only the project, the system and developer tools
    network: "localhost",    // or "none"
    denyRead: ["~/notes"],   // hide more
  },
}
```

A file can only make these stricter. To loosen them for one run, use the flags: `--write anywhere`, `--read DIR`, `--network any`. The
status line says when the sandbox is strict.

## Making room

- `allowRead: ["~/.aws"]` in your own file makes a protected path readable again. A project's file cannot.
- `ask --no-sandbox` turns the sandbox off for one run.
- SwiftPM needs `--disable-sandbox` to build inside ask's sandbox; ask's own sandbox still applies.

## When the model asks for more

The model can ask to narrow its own sandbox for a call, or for the rest of the conversation; that needs no approval. If it asks for **more**
than the sandbox allows, ask puts the question to you above the input, with a box for each answer: **Allow this time**, **Allow for
the session**, **Deny**. Up and Down move, Space or a click checks a box (or press its number, or `y`, `a`, `n`), Enter confirms; Esc denies at once.
Undoing a narrowing asks a plain Yes or No, and an MCP tool marked destructive starts with Deny checked. The question stays in the
conversation with your answer. `ask -p` refuses,
since nobody is there to answer. Anything granted this way lasts only until `/new`, `/resume` or a restart.
