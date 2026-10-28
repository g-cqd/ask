# ask

A fast, light terminal coding agent for macOS, written in Swift.

## Build

Needs macOS 26 and Swift 6.4.

```sh
git clone https://github.com/g-cqd/ask.git && cd ask
swift build -c release
cp .build/release/ask /usr/local/bin/
```

## Start

```sh
ask login claude   # or codex, agy; skip it to use Apple's on-device model
ask                # in your project
```

Type `/` for commands, `@` for files. Esc twice stops a turn; `/quit` leaves.

## Learn more

- [User guide](docs/README.md): keys, sessions, configuration, providers, sandbox.
- [Development](development/WHITE-PAPER.md): how ask is built, and [how to contribute](CONTRIBUTING.md).

[MIT](LICENSE)
