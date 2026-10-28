#!/bin/sh
# Reproduces the Seatbelt probes behind ADR-0020. Run on the macOS release in question; prints one line per claim.
set -u
T=$(mktemp -d); mkdir -p "$T/work" "$T/secret"; echo s3cret > "$T/secret/key"
W=$(cd "$T/work" && pwd -P); S=$(cd "$T/secret" && pwd -P)
run() { label="$1"; shift; out=$("$@" 2>&1); code=$?; printf '%-48s exit=%-3s %s\n' "$label" "$code" "$(echo "$out" | head -1 | cut -c1-60)"; }
run "deny network*: curl" sandbox-exec -p '(version 1)(allow default)(deny network*)' curl -sS -m 5 -o /dev/null https://example.com
P='(version 1)(allow default)(deny file-write*)(allow file-write* (subpath (param "WORK")) (literal "/dev/null"))'
run "write inside WORK (param)" sandbox-exec -D WORK="$W" -p "$P" sh -c "echo ok > $W/a"
run "write outside WORK" sandbox-exec -D WORK="$W" -p "$P" sh -c "echo no > $T/outside"
run "quote in a param is data" sandbox-exec -D WORK='/tmp") (allow file-write* (subpath "/' -p "$P" sh -c "echo no > $T/evil"
run "non-canonical path in profile" sandbox-exec -p "(version 1)(allow default)(deny file-write*)(allow file-write* (subpath \"$T/work\"))" sh -c "echo l > $W/l"
R="(version 1)(allow default)(deny file-read* (subpath \"$S\"))"
run "read denied, inherited by children" sandbox-exec -p "$R" bash -c "cat $S/key"
run "nested sandbox-exec" sandbox-exec -p '(version 1)(allow default)' sandbox-exec -p "$R" true
rm -rf "$T"
