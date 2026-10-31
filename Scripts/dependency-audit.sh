#!/bin/sh
# Each target imports only what it declares, and declares only what it imports (roadmap 0166): swift-dependency-audit from a pinned
# release (version and archive SHA-256), installed on first use. A module that is only reachable through another target's dependency
# still builds, which is why the compiler does not catch it.
#
#   Scripts/dependency-audit.sh            install if absent, then audit the package
#   Scripts/dependency-audit.sh install    install only
#
# FoundationModels is a system framework, not a package dependency, so it is whitelisted.
# Exit: 0 clean, 1 a missing or unused dependency, 2 the tool could not be installed.
set -eu

VERSION=2.0.8
SHA256=f55573e86e0d4d28b6ba695e1dfbdfcdb52e1a1b8e6e19473d9a659fa813a5a6
ARCHIVE="swift-dependency-audit-$VERSION-macos-universal.tar.gz"

case "$(uname -s)" in
    Darwin) cache_root="$HOME/Library/Caches" ;;
    *) printf '[FAIL] the pinned swift-dependency-audit archive is for macOS\n' >&2; exit 2 ;;
esac
dir="$cache_root/g-cqd-deps/swift-dependency-audit-$VERSION"
tool="$dir/swift-dependency-audit"

if [ ! -x "$tool" ]; then
    scratch=$(mktemp -d)
    curl -fsSL --retry 3 -o "$scratch/$ARCHIVE" \
        "https://github.com/tonyarnold/swift-dependency-audit/releases/download/v$VERSION/$ARCHIVE" \
        || { rm -rf "$scratch"; printf '[FAIL] could not fetch %s\n' "$ARCHIVE" >&2; exit 2; }
    actual=$(shasum -a 256 "$scratch/$ARCHIVE" | cut -d' ' -f1)
    if [ "$actual" != "$SHA256" ]; then
        rm -rf "$scratch"
        printf '[FAIL] %s has SHA-256 %s, not the pinned %s\n' "$ARCHIVE" "$actual" "$SHA256" >&2
        exit 2
    fi
    tar -xzf "$scratch/$ARCHIVE" -C "$scratch"
    mkdir -p "$dir"
    mv "$scratch/swift-dependency-audit-$VERSION-macos-universal/swift-dependency-audit" "$tool"
    rm -rf "$scratch"
fi
[ "${1:-}" = install ] && exit 0

cd "$(dirname "$0")/.."
"$tool" . --no-color --quiet --whitelist FoundationModels
