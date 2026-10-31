#!/bin/sh
# Mutation testing of the Sources files changed against BASE (roadmap 0166), with swift-mutation-testing from a pinned release.
#
#   Scripts/mutate-changed.sh [BASE]          changed files against BASE (default origin/main), committed or not
#   Scripts/mutate-changed.sh --all           every file, and the baseline rewritten (the weekly run)
#   Scripts/mutate-changed.sh install         install the tool only
#
# One plan for the package, kept to the changed files and split by target: Sources/AskTUI/... runs with AskTUITests. The executable
# target (Sources/ask) has no test target, so its files are left out and said so. A run fails on any surviving mutant not in
# development/mutation-baseline.json (--max-new-survivors 0), which --all rewrites; until a full run writes it, it lists none, so every
# survivor in a changed file counts. Verdicts are cached per mutant by the tool, so a rerun tests only what changed. The tool reports
# every kill here as "killed without activation": its activation probe does not reach SwiftPM's test processes, so that warning is
# not gated on.
#
# Exit: 0 no new survivor, 1 new survivors (or a failed run), 2 the tool could not be installed.
set -eu

VERSION=v1.6.4
SHA256=c8a0690598766bba4a5f4616f8f99b8909ddf884bbcdb41c83ace62451cd8303
ARCHIVE="swift-mutation-testing-$VERSION-macos.tar.gz"
BASELINE=development/mutation-baseline.json

case "$(uname -s)" in
    Darwin) cache_root="$HOME/Library/Caches" ;;
    *) cache_root="${XDG_CACHE_HOME:-$HOME/.cache}" ;;
esac
dir="$cache_root/g-cqd-mutation/swift-mutation-testing-$VERSION"
tool="$dir/swift-mutation-testing"

install_tool() {
    [ -x "$tool" ] && return 0
    scratch=$(mktemp -d)
    curl -fsSL --retry 3 -o "$scratch/$ARCHIVE" \
        "https://github.com/ericodx/swift-mutation-testing/releases/download/$VERSION/$ARCHIVE" \
        || { rm -rf "$scratch"; printf '[FAIL] could not fetch %s\n' "$ARCHIVE" >&2; exit 2; }
    actual=$(shasum -a 256 "$scratch/$ARCHIVE" | cut -d' ' -f1)
    if [ "$actual" != "$SHA256" ]; then
        rm -rf "$scratch"
        printf '[FAIL] %s has SHA-256 %s, not the pinned %s\n' "$ARCHIVE" "$actual" "$SHA256" >&2
        exit 2
    fi
    tar -xzf "$scratch/$ARCHIVE" -C "$scratch"
    mkdir -p "$dir"
    mv "$scratch/swift-mutation-testing" "$tool"
    rm -rf "$scratch"
}

install_tool
[ "${1:-}" = install ] && exit 0

cd "$(dirname "$0")/.."
# The tool takes report and baseline paths relative to the project, so the run's files live in the build directory.
work=.build/mutation
rm -rf "$work"
mkdir -p "$work"

if [ "${1:-}" = --all ]; then
    changed=$(git ls-files 'Sources/*.swift')
else
    base="${1:-origin/main}"
    # Committed since BASE, staged or not yet staged; deleted files have no mutants.
    changed=$( (git diff --name-only --diff-filter=AMR "$base" -- 'Sources/*.swift'; git ls-files --others --exclude-standard 'Sources/*.swift') | sort -u)
fi
if [ -z "$changed" ]; then
    echo "[OK] no changed Sources files"
    exit 0
fi

"$tool" plan . --sources-path Sources --output "$work/plan.json" --quiet
printf '%s\n' "$changed" > "$work/changed.txt"

# One plan per target, each kept to the changed files of that target; the targets with mutants are printed.
targets=$(python3 - "$work" <<'PY'
import collections, json, pathlib, sys
work = pathlib.Path(sys.argv[1])
plan = json.loads((work / "plan.json").read_text())
changed = set((work / "changed.txt").read_text().split())
tests = {path.name for path in pathlib.Path("Tests").iterdir() if path.is_dir()}
by_target = collections.defaultdict(list)
for mutant in plan["mutants"]:
    if mutant["file"] in changed:
        by_target[mutant["file"].split("/")[1]].append(mutant)
for target, mutants in sorted(by_target.items()):
    if target + "Tests" not in tests:
        files = sorted({m["file"] for m in mutants})
        print(f"[SKIP] {target} has no test target: {', '.join(files)}", file=sys.stderr)
        continue
    files = {m["file"] for m in mutants}
    kept = dict(plan, mutants=mutants, files=[f for f in plan["files"] if f["path"] in files])
    (work / f"plan-{target}.json").write_text(json.dumps(kept))
    print(f"{target} {len(mutants)}")
PY
)
if [ -z "$targets" ]; then
    echo "[OK] no mutants in the changed files"
    exit 0
fi

status=0
printf '%s\n' "$targets" | while read -r target count; do
    printf '== %s: %s mutants\n' "$target" "$count"
    extra=""
    [ "${1:-}" = --all ] && extra="--write-baseline $work/baseline-$target.json"
    # shellcheck disable=SC2086 # the gate and extra options are word lists
    "$tool" run . --plan "$work/plan-$target.json" --target "${target}Tests" --build-timeout 300 \
        --markdown-output "$work/report-$target.md" --baseline "$BASELINE" --max-new-survivors 0 $extra \
        || echo "$target" >> "$work/failed"
    [ -f "$work/report-$target.md" ] && cat "$work/report-$target.md"
done
if [ "${1:-}" = --all ]; then
    python3 - "$work" "$BASELINE" <<'PY'
import json, pathlib, sys
work, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
parts = [json.loads(p.read_text()) for p in sorted(work.glob("baseline-*.json"))]
if parts:
    # One baseline for the package: every target's survivors, and the lowest score (only --max-score-drop reads it).
    merged = dict(parts[0], undetected=[u for part in parts for u in part["undetected"]],
                  score=min(part["score"] for part in parts))
    out.write_text(json.dumps(merged, indent=1, sort_keys=True) + "\n")
    print(f"[OK] baseline written: {out}")
PY
fi
if [ -f "$work/failed" ]; then
    printf '[FAIL] new surviving mutants, or a failed run, in: %s\n' "$(tr '\n' ' ' < "$work/failed")"
    status=1
else
    echo "[OK] no new surviving mutant"
fi
exit $status
