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

VERSION_DEADWOOD=0.10.2
SHA_DEADWOOD=6a69fde41051a4dde558f3e2747addf85fcc7e0fa61479a35e5ececd3fb78ab2
VERSION_DOLLY=0.10.3
SHA_DOLLY=9ca8e0d236c3a273b5ef3351d04857b9ae191e63356da9919cfc800f0863deb6
VERSION_ARCLEAK=0.11.0
SHA_ARCLEAK=7829e2efd4c4cd91c947962c6052c5949d22551352e074aefcf43f41e547e139

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
