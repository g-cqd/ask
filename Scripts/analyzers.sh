#!/bin/sh
# Static analyzers for this package: deadwood (unused code), dolly (duplicated code) and arcleak (retain
# cycles and leaks), all from github.com/g-cqd, all syntax-level so they need no build.
#
#   Scripts/analyzers.sh            install the pinned releases if absent, then run all three
#   Scripts/analyzers.sh install    install only
#
# Each tool is pinned to a release and to the SHA-256 of its macOS arm64 archive, and the pin is checked
# before anything is executed. Baseline fingerprints move between versions, so an unpinned tool would make a
# gate go red for no change of ours. To upgrade: change VERSION and SHA together, run, and read the diff of
# findings before committing.
#
# Exit: 0 clean, 1 a tool found something, 2 a tool could not be installed or run.
set -eu

VERSION_DEADWOOD=0.11.1
SHA_DEADWOOD=a1d994ed94fa90d099674d4ece67c4e8fb73feb3f7b1bb2729efd753e1e0fdff
VERSION_DOLLY=0.11.0
SHA_DOLLY=5e20c29c15e3c40a9d25fe873205230933cfe7bf97e7d229acb0ee0b63336701
VERSION_ARCLEAK=0.12.0
SHA_ARCLEAK=50c583159eb06ce26bc556473bd632b572da48f3da245f1c30c73bf5b9e88ae1

# Outside the repository, so a verification worktree reuses the download instead of repeating it.
CACHE="${ASK_ANALYZERS_DIR:-$HOME/Library/Caches/ask/analyzers}"

# What each tool analyzes. Benchmarks/ is left out: the Benchmark plugin finds a global named `benchmarks` by
# name, which no syntax-level analyzer can see, so every benchmark looks like dead code.
# The corpus is otherwise the whole package: reachability and clone detection are
# whole-program, and a smaller corpus makes live code look dead.
CORPUS="Sources Tests"

fail() { printf '[FAIL] %s\n' "$1" >&2; exit "${2:-1}"; }

install_tool() {
    tool=$1 version=$2 sha=$3
    dir="$CACHE/$tool-$version"
    [ -x "$dir/$tool" ] && return 0
    [ "$(uname -s)-$(uname -m)" = "Darwin-arm64" ] || fail "$tool: only macOS arm64 is pinned here" 2
    name="$tool-$version-macos-arm64"
    scratch=$(mktemp -d)
    trap 'rm -rf "$scratch"' EXIT
    printf '==> installing %s %s\n' "$tool" "$version"
    curl -fsSL --retry 3 -o "$scratch/$name.tar.gz" \
        "https://github.com/g-cqd/$tool/releases/download/v$version/$name.tar.gz" \
        || fail "$tool: download failed" 2
    actual=$(shasum -a 256 "$scratch/$name.tar.gz" | cut -d' ' -f1)
    [ "$actual" = "$sha" ] || fail "$tool: archive hash $actual is not the pinned $sha" 2
    tar -xzf "$scratch/$name.tar.gz" -C "$scratch"
    mkdir -p "$dir"
    cp "$scratch/$name/$tool" "$dir/$tool"
    reported=$("$dir/$tool" --version 2>/dev/null || true)
    [ "$reported" = "$version" ] || { rm -rf "$dir"; fail "$tool reports '$reported', not $version" 2; }
}

install_tool deadwood "$VERSION_DEADWOOD" "$SHA_DEADWOOD"
install_tool dolly "$VERSION_DOLLY" "$SHA_DOLLY"
install_tool arcleak "$VERSION_ARCLEAK" "$SHA_ARCLEAK"
[ "${1:-}" = "install" ] && exit 0

run() {
    tool=$1 version=$2
    printf '==> %s %s\n' "$tool" "$version"
    # --strict: a warning fails, a note never does. Each tool reads its own .<tool>.json.
    # shellcheck disable=SC2086
    "$CACHE/$tool-$version/$tool" analyze --strict --no-cache --relative-to . $CORPUS \
        || failed=1
}

failed=0
run deadwood "$VERSION_DEADWOOD"
run dolly "$VERSION_DOLLY"
run arcleak "$VERSION_ARCLEAK"
[ "$failed" -eq 0 ] || fail "a static analyzer reported findings (accept one with a directive and a reason, never silently)"
printf '[OK] analyzers clean\n'
