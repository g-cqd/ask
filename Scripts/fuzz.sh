#!/bin/sh
# Coverage-guided fuzzing of the parsers that read bytes ask did not write (roadmap 0232): libFuzzer over `Fuzz/`'s targets, all at
# once, each for SECONDS. A finding (a crash, a trap, a hang, or a property the code promises that did not hold) stops that target,
# leaves its input in .build/fuzz/<target>/, and fails the run: the input becomes a red test before the fix.
#
#   Scripts/fuzz.sh [SECONDS] [TARGET...]     SECONDS default 60; TARGET: sse session mcp terminal index text (default: all)
#
# Needs a swift.org toolchain (Xcode's has no libFuzzer). ask's own modules are instrumented (ASK_FUZZ in its manifest); AemiJSON,
# AemiSearch and TerminalKit are not, so `index` and the terminal's input run without guidance. The corpus each target grows is kept
# in ${ASK_FUZZ_CORPUS:-~/Library/Caches/ask/fuzz}/<target> between runs; Fuzz/Seeds/<target> starts it.
set -eu
cd "$(dirname "$0")/.."
seconds="${1:-60}"
[ "$#" -gt 0 ] && shift
[ "$#" -gt 0 ] || set -- sse session mcp terminal index text
corpora="${ASK_FUZZ_CORPUS:-$HOME/Library/Caches/ask/fuzz}"
root="$PWD"
out="$root/.build/fuzz"
rm -rf "$out"
mkdir -p "$out"
(cd Fuzz && ASK_FUZZ=1 swift build -c release --product ask-fuzz > "$out/build.log" 2>&1) || { tail -20 "$out/build.log"; exit 2; }
binary="$(cd Fuzz && ASK_FUZZ=1 swift build -c release --show-bin-path)/ask-fuzz"

for target in "$@"; do
    mkdir -p "$corpora/$target" "$out/$target" "Fuzz/Seeds/$target"
    (
        cd "$out/$target"
        ASK_FUZZ_TARGET="$target" ASK_FUZZ_SEEDS="$corpora/$target" "$binary" "$corpora/$target" "$root/Fuzz/Seeds/$target" \
            -dict="$root/Fuzz/Dictionaries/json.dict" -max_total_time="$seconds" -max_len=65536 -timeout=10 -rss_limit_mb=2048 \
            -print_final_stats=1 > run.log 2>&1 && echo 0 > status || echo "$?" > status
    ) &
done
wait

failed=0
for target in "$@"; do
    status=$(cat "$out/$target/status")
    stats=$(grep -aE '^#[0-9]+.*(DONE|cov:)' "$out/$target/run.log" | tail -1 | sed -E 's/^#([0-9]+).*cov: ([0-9]+).*corp: ([0-9]+).*/\1 runs, cov \2, corpus \3/')
    if [ "$status" = 0 ]; then
        echo "PASS $target: $stats"
    else
        failed=1
        echo "FAIL $target (exit $status): $(grep -aE 'PROPERTY BROKEN|Fatal error|ERROR: libFuzzer|SUMMARY' "$out/$target/run.log" | head -2 | tr '\n' ' ' | cut -c1-240)"
        find "$out/$target" -maxdepth 1 \( -name 'crash-*' -o -name 'timeout-*' -o -name 'oom-*' -o -name 'leak-*' \) | sed 's/^/     input: /'
    fi
done
exit "$failed"
