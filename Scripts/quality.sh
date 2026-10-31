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
# Static analysis (unused code, duplicated code, retain cycles) is `Scripts/analyzers.sh`, which downloads its own
# pinned tools; unlike swift-format and SwiftLint they are not expected to be installed.
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
    "$SF" lint --recursive --configuration .swift-format --strict Sources Tests Benchmarks/Benchmarks \
        || fail "formatting drift — run Scripts/quality.sh to fix"
else
    printf '==> swift-format (format)\n'
    "$SF" format --in-place --recursive --configuration .swift-format Sources Tests Benchmarks/Benchmarks
fi

printf '==> swiftlint (metrics, --strict)\n'
swiftlint lint --strict --config .swiftlint.yml Sources Tests Benchmarks/Benchmarks \
    || fail "SwiftLint metric violations"

printf '==> static analyzers (deadwood, dolly, arcleak)\n'
# Pinned releases, installed on first use; see Scripts/analyzers.sh. They read source, so they need no build and
# finish in well under a second, which is why they run before the tests rather than after.
Scripts/analyzers.sh || fail "static analyzer findings"

printf '==> declared dependencies (swift-dependency-audit)\n'
# Every import declared by its target and every declared dependency imported; see Scripts/dependency-audit.sh.
Scripts/dependency-audit.sh || fail "a target imports what it does not declare, or declares what it does not import"

printf '==> measurement harness guards (Python standard library)\n'
need python3 "Install Python 3 to run the external measurement guards."
python3 Scripts/test-measurements.py || fail "measurement harness guards"

printf '==> documentation numbers and landing workflow guards\n'
python3 Scripts/check-records.py || fail "duplicate documentation numbers"
python3 -B Scripts/test-workflow.py || fail "landing workflow guards"
python3 -B Scripts/test-sign.py || fail "signing script guards"

printf '==> target layering (ADR-0009)\n'
python3 -B Scripts/test-layers.py || fail "layering check self-test"
python3 -B Scripts/check-layers.py || fail "a target depends on one ADR-0009's layering does not allow"

printf '==> build and test (release)\n'
# Explicit testability for optimized tests (ADR-0006). Benchmark/shipping binaries are built
# separately with `swift build -c release`; do not treat a testable build as byte-identical.
swift test -c release --enable-testable-imports

printf '\n[OK] clean\n'