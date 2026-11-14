#!/bin/sh
# Builds ask for release, measures the five budgets, and installs it only when they hold (roadmap 0232). The owner, 2026-11-14: the
# budgets are checked where a build ships, and until there is a release (roadmap 0070) that is this install.
#
#   Scripts/install.sh [DIRECTORY]     DIRECTORY default ~/.local/bin
#
# The build is Scripts/build-release.sh's: the shipping one, signed when ASK_SIGNING_IDENTITY is set. The budgets are measured on
# that binary under load, as every budget check is (ADR-0122). A build over budget, a measurement that did not finish, or a copy that
# does not run is not installed, and the ask already there stays as it was. The new one is staged beside the target and moved over
# it, so the target is never half-written and a running ask keeps the file it started from.
set -eu
cd "$(dirname "$0")/.."
directory="${1:-$HOME/.local/bin}"
binary=.build/release/ask

Scripts/build-release.sh --product ask
if ! python3 Scripts/measure-budgets.py "$binary" 12; then
    echo "Not installed: a budget is exceeded or could not be measured (above). $directory/ask is as it was." >&2
    exit 1
fi

mkdir -p "$directory"
staged=$(mktemp "$directory/.ask.XXXXXX")
trap 'rm -f "$staged"' EXIT
install -m 755 "$binary" "$staged"
if ! "$staged" --help > /dev/null 2>&1; then
    echo "Not installed: the staged copy does not run. $directory/ask is as it was." >&2
    exit 1
fi
mv "$staged" "$directory/ask"

commit=$(git rev-parse --short HEAD 2> /dev/null || echo "an unknown commit")
[ -z "$(git status --porcelain 2> /dev/null)" ] || commit="$commit, with changes not committed"
echo "Installed $directory/ask, built from $commit."
