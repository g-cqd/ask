#!/bin/sh
# The quality gate for this package. One entry point, so a check cannot be forgotten because
# someone remembered a different command.
#
#   Scripts/quality.sh            format, lint, then build and test
#   Scripts/quality.sh --check    verify only: fails if the tree is not already canonical
#
# The rules are NOT this script's opinion. `.swift-format` and `.swiftlint.yml` are Aemi's canonical
# configuration, copied by `Aemi/scripts/sync-config.sh`, so every package in the ecosystem formats
# and gates size/complexity identically. SwiftFormat owns style; SwiftLint is configured with
# `only_rules`, so it contributes the size and complexity metrics that formatting cannot express and
# can never fight the formatter over a style question.
#
# Exit codes: 0 clean, 1 drift or a violation, 2 a tool is missing.
set -eu

check_only=0
[ "${1:-}" = "--check" ] && check_only=1

fail() { printf '\n[FAIL] %s\n' "$1" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || { printf '[FAIL] %s not found. %s\n' "$1" "$2" >&2; exit 2; }; }

SF=$(command -v swift-format || xcrun -f swift-format 2>/dev/null || true)
[ -n "$SF" ] || { printf '[FAIL] swift-format not found. Install a Swift 6.4 toolchain.\n' >&2; exit 2; }
need swiftlint "Install with: brew install swiftlint"

[ -f .swift-format ] || fail ".swift-format missing — sync it with Aemi/scripts/sync-config.sh"
[ -f .swiftlint.yml ] || fail ".swiftlint.yml missing — sync it with Aemi/scripts/sync-config.sh"

if [ "$check_only" -eq 1 ]; then
    printf '==> swift-format (check)\n'
    "$SF" lint --recursive --configuration .swift-format --strict Sources Tests \
        || fail "formatting drift — run Scripts/quality.sh to fix"
else
    printf '==> swift-format (format)\n'
    "$SF" format --in-place --recursive --configuration .swift-format Sources Tests
fi

printf '==> swiftlint (metrics, --strict)\n'
swiftlint lint --strict --config .swiftlint.yml Sources Tests \
    || fail "SwiftLint metric violations"

printf '==> build and test (release)\n'
# Release, always: this package exists for latency, and a debug build measures a program nobody runs.
swift build -c release
swift test -c release

printf '\n[OK] clean\n'