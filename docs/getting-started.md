# Getting started

## Install

There are no binary releases yet, so you build ask from source. You need macOS 26 and Swift 6.4.

```sh
git clone https://github.com/g-cqd/ask.git
cd ask
swift build -c release
cp .build/release/ask /usr/local/bin/   # or anywhere on your PATH
```

## Sign in

ask can start without an account: when nothing is signed in, it uses Apple's on-device model, which needs no key and costs nothing, but has
a small context window, so it suits questions and short edits.

To use a hosted model, sign in once:

```sh
ask login claude      # a Claude subscription, in the browser
ask login codex       # a ChatGPT subscription
ask login agy         # a Google account, for Antigravity
```

You can also sign in from inside ask with `/login`, or use an API key: see [Providers and accounts](providers.md).

## First run

Open a terminal in your project and run:

```sh
ask
```

Type what you want and press Enter. The model reads, edits and runs commands in the project, inside a [sandbox](sandbox.md) that keeps it
away from ask's own files and your secret stores. Each tool call shows as a block you can click to open.

A few things to try:

- Type `/` to see the commands, and `@` to point at a file.
- Press Enter while the model is working to steer it; your message is sent after its current step.
- Press Esc twice, or Ctrl+C, to stop a turn.
- Leave with `/quit`, or Ctrl+C twice.

Everything is saved as you go. `ask -c` continues the last conversation in this project; see [Sessions](sessions.md).

## One prompt from the shell

```sh
ask -p "summarise the changes on this branch"
```

`-p` runs one prompt with the same tools and sandbox, prints the answer and exits. A question the sandbox would put to you is refused
instead, since nobody is there to answer.

## Next

- [The screen and its keys](screen.md)
- [Configuration](configuration.md): `ask config` shows every setting and where it came from.
