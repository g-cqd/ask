#!/bin/sh
# The PTY sweep (roadmap 0211): every Scripts/probe-*.py against one release build, each with a time limit; one line per probe and a
# non-zero exit when any fails. A probe listed in Scripts/sweep-skip.txt (name, then why) is skipped and said so: those need what a
# sweep cannot give (a real account, the owner's keychain, a service on the network).
#
#   Scripts/sweep.sh [--jobs N] [--timeout SECONDS] [--skip-build] [PROBE...]   results in .build/sweep (summary.txt, one log each)
set -eu

cd "$(dirname "$0")/.."
jobs=4
limit=300
build=1
while [ "$#" -gt 0 ]; do
    case "$1" in
        --jobs) jobs="$2"; shift 2 ;;
        --timeout) limit="$2"; shift 2 ;;
        --skip-build) build=0; shift ;;
        *) break ;;
    esac
done

out=.build/sweep
rm -rf "$out"
mkdir -p "$out/logs"
if [ "$build" = 1 ]; then
    swift build -c release --product ask --force-resolved-versions > "$out/build.log" 2>&1 || { tail -20 "$out/build.log"; exit 2; }
fi
binary="$PWD/.build/release/ask"
Scripts/probe-deps.sh > "$out/deps.log" 2>&1 || { cat "$out/deps.log"; exit 2; }

if [ "$#" -gt 0 ]; then
    printf '%s\n' "$@" > "$out/probes.txt"
else
    find Scripts -maxdepth 1 -name 'probe-*.py' | sort > "$out/probes.txt"
fi

: > "$out/summary.txt"
# JOBS probes at once, each appending its line; then the summary, sorted, and the verdict.
xargs -P "$jobs" -n 1 python3 Scripts/sweep_one.py "$out" "$binary" "$limit" < "$out/probes.txt"
# A probe that failed beside others runs again alone: passing then, it is FLAKY (said, not failed): it waits on time the others took.
grep -E '^(FAIL|TIME) ' "$out/summary.txt" | awk '{print $3}' > "$out/again.txt" || true
grep -vE '^(FAIL|TIME) ' "$out/summary.txt" > "$out/kept.txt" || true
: > "$out/alone.txt"
while read -r name; do
    mv "$out/logs/$name.log" "$out/logs/$name.parallel.log"
    python3 Scripts/sweep_one.py "$out" "$binary" "$limit" "Scripts/$name.py" 2> /dev/null
done < "$out/again.txt"
if [ -s "$out/again.txt" ]; then
    tail -n "$(wc -l < "$out/again.txt")" "$out/summary.txt" | sed 's/^PASS /FLAKY/' > "$out/alone.txt"
fi
cat "$out/kept.txt" "$out/alone.txt" | sort > "$out/summary.txt"
cat "$out/summary.txt"
failed=$(grep -cE '^(FAIL|TIME) ' "$out/summary.txt" || true)
passed=$(grep -c '^PASS ' "$out/summary.txt" || true)
flaky=$(grep -c '^FLAKY' "$out/summary.txt" || true)
skipped=$(grep -c '^SKIP ' "$out/summary.txt" || true)
printf '%s passed, %s flaky (passed alone), %s failed, %s skipped\n' "$passed" "$flaky" "$failed" "$skipped"
[ "$failed" = 0 ]
