#!/bin/sh
# Mutation testing (roadmap 0166) with litmus (https://github.com/g-cqd/litmus), from a pinned release. In CI only (the owner,
# 2026-11-10 and 2026-11-16): a run takes a runner for hours, and it rewrites the checkout it runs in.
#
#   Scripts/mutate-changed.sh [BASE]        the Sources files changed against BASE (default origin/main)
#   Scripts/mutate-changed.sh --all K/N     shard K of N of every file (the weekly run, one job per shard): its run is left in
#                                           $LITMUS_OUTPUT for the merge
#   Scripts/mutate-changed.sh merge DIR     the shards' runs under DIR as one run, and the baseline written from it
#   Scripts/mutate-changed.sh install       install the tool only
#
# litmus rewrites a batch of mutants into the sources, each behind a switch of its own, builds once and runs the tests that can
# reach a mutant with only that one switched on. A shard is whole targets (`Sources/AskTUI`), so a shard rebuilds only what it
# mutates. The executable target (Sources/ask: the options and subcommands) has no test target, so its files are left out.
#
# A changed-files run fails on a surviving or unreached mutant that development/mutation-baseline.json does not hold: kill it with
# a test. Until a full run has written that file, every one counts. A run stops starting work at its budget and says how many
# mutants it did not run, the changed lines first, so a job ends by itself with what it found instead of being cancelled with
# nothing.
#
# Exit: 0 nothing new, 1 new survivors, 2 not in CI or the tool could not be installed; any other is litmus's own (70: a run whose
# evidence is incomplete).
set -eu

VERSION=0.3.2
SHA256=4e273655bc89a2f87b7993f1640ac835286fcd1d9f288aeaaacb8b9aea1af288
ARCHIVE="litmus-$VERSION-macos-arm64.tar.gz"
BASELINE=development/mutation-baseline.json

if [ "${GITHUB_ACTIONS:-}" != true ]; then
    echo "[FAIL] mutation testing runs in CI only: gh workflow run mutation.yml -R g-cqd/ask" >&2
    exit 2
fi

dir="$HOME/Library/Caches/g-cqd-mutation/litmus-$VERSION"
tool="$dir/litmus"

install_tool() {
    [ -x "$tool" ] && return 0
    scratch=$(mktemp -d)
    curl -fsSL --retry 3 -o "$scratch/$ARCHIVE" "https://github.com/g-cqd/litmus/releases/download/v$VERSION/$ARCHIVE" \
        || { rm -rf "$scratch"; printf '[FAIL] could not fetch %s\n' "$ARCHIVE" >&2; exit 2; }
    actual=$(shasum -a 256 "$scratch/$ARCHIVE" | cut -d' ' -f1)
    if [ "$actual" != "$SHA256" ]; then
        rm -rf "$scratch"
        printf '[FAIL] %s has SHA-256 %s, not the pinned %s\n' "$ARCHIVE" "$actual" "$SHA256" >&2
        exit 2
    fi
    tar -xzf "$scratch/$ARCHIVE" -C "$scratch"
    mkdir -p "$dir"
    mv "$scratch/litmus-$VERSION-macos-arm64/litmus" "$tool"
    rm -rf "$scratch"
}

# The report litmus printed: in the log, and on the run's summary page.
said() {
    cat "$1"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then cat "$1" >> "$GITHUB_STEP_SUMMARY"; fi
}

install_tool
[ "${1:-}" = install ] && exit 0

cd "$(dirname "$0")/.."
# A run's directory must be new and outside the sources; the workflow uploads it.
output="${LITMUS_OUTPUT:-${RUNNER_TEMP:-/tmp}/litmus-run}"

if [ "${1:-}" = merge ]; then
    "$tool" merge "$2"/*/ --output "$output"
    # The whole run's verdict, for the summary. Its survivors are what the baseline is for, so they do not fail it; a run that is
    # not whole does (a mutant with no verdict: 70). What a budget left out is said there, and is not in the baseline.
    status=0
    "$tool" analyze . --results "$output/run.pb" --format markdown > "$output/report.md" || status=$?
    said "$output/report.md"
    "$tool" analyze . --results "$output/run.pb" --write-baseline "$BASELINE"
    exit "$status"
fi

# Sources only: the repository's other packages (Benchmarks, Fuzz) are not this one's. In place, since the checkout is the
# runner's own and thrown away, and the tests then find the repository they read where it is. A cold build of everything took a
# hosted runner close to ten minutes (the runs of 2026-11-12 to 15), so a build gets thirty.
common="--trust-project --workspace in-place --only-path Sources/** --exclude-path Sources/ask/** --build-timeout 1800"
status=0
if [ "${1:-}" = --all ]; then
    # shellcheck disable=SC2086 # the options are a word list; set -f keeps their globs for litmus
    (set -f; "$tool" run . $common --shard "$2" --budget "${LITMUS_BUDGET:-18000}" --output "$output" --report markdown) \
        > "$output.md" || status=$?
    said "$output.md"
    # A shard that ran to its end has done its part, whatever its verdict (70: a mutant with none): the merge judges the whole,
    # once. One that did not (the suite failing with no mutant active, a build that never worked) fails here, where its log is.
    if [ "$status" != 0 ] && python3 -c 'import json, sys; sys.exit(json.load(open(sys.argv[1])).get("complete") is not True)' \
        "$output/run.json" 2> /dev/null; then
        echo "::warning::litmus ended with $status on shard $2, its run complete: left to the merge"
        status=0
    fi
    exit "$status"
fi

# shellcheck disable=SC2086 # as above
(set -f; "$tool" run . $common --diff-base "${1:-origin/main}" --diff-scope files --budget "${LITMUS_BUDGET:-10800}" \
    --output "$output" --report markdown --baseline "$BASELINE" --gate new-survivors) > "$output.md" || status=$?
said "$output.md"
if [ "$status" = 1 ]; then echo "[FAIL] new surviving mutants: kill each with a test"; fi
exit "$status"
