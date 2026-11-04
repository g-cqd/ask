#!/bin/sh
# The quality gate for this package. One entry point, so a check cannot be forgotten because
# someone remembered a different command.
#
#   Scripts/quality.sh            format, then every check of --check, in one run
#   Scripts/quality.sh --check    verify only: fails if the tree is not already canonical (CI)
#
# The rules are NOT this script's opinion. `.swift-format` and `.swiftlint.yml` are Aemi's canonical
# configuration, copied by `Aemi/scripts/sync-config.sh`, so every package in the ecosystem formats
# and gates size/complexity identically. SwiftFormat owns style; SwiftLint is configured with
# `only_rules`, so it contributes the size and complexity metrics that formatting cannot express and
# can never fight the formatter over a style question.
#
# The checks themselves are CI's (`.ci/action.json`, run by `.ci/swift-ci`, which downloads its pinned analyzers); this script
# formats first and adds the optimized tests.
#
# Exit codes: 0 clean, 1 drift or a violation, 2 a tool is missing.
set -eu

check_only=0
[ "${1:-}" = "--check" ] && check_only=1

fail() { printf '\n[FAIL] %s\n' "$1" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || { printf '[FAIL] %s not found. %s\n' "$1" "$2" >&2; exit 2; }; }

# One toolchain, named by .swift-version, here and in CI: the compiler must be it, and swift-format comes from it (xcrun follows
# TOOLCHAINS, which a CI toolchain install sets), so a format or a build never depends on which other toolchain is on PATH.
wanted=$(cat .swift-version)
running=$(swift --version 2>/dev/null | sed -n 's/.*Swift version \([0-9.]*\).*/\1/p' | head -1)
[ "$running" = "$wanted" ] || { printf '[FAIL] swift is %s; .swift-version names %s.\n' "${running:-missing}" "$wanted" >&2; exit 2; }
if [ "$(uname -s)" = Darwin ]; then SF=$(xcrun -f swift-format 2>/dev/null || true); else SF=$(command -v swift-format || true); fi
[ -n "$SF" ] || { printf '[FAIL] swift-format not found in the Swift %s toolchain.\n' "$wanted" >&2; exit 2; }

[ -f .swift-format ] || fail ".swift-format missing — sync it with Aemi/scripts/sync-config.sh"
[ -f .swiftlint.yml ] || fail ".swiftlint.yml missing — sync it with Aemi/scripts/sync-config.sh"

# Formatting first, once, then the same check `--check` makes: what formatting cannot fix (a line too long to wrap, say) still fails
# here, before anything slower runs.
if [ "$check_only" -eq 0 ]; then
    printf '==> swift-format (format)\n'
    "$SF" format --in-place --recursive --configuration .swift-format Sources Tests Benchmarks/Benchmarks
fi
printf '==> CI quality (.ci/swift-ci run quality)\n'
# What CI's quality job runs, from .ci/action.json: swift-format --strict, SwiftLint metrics, the pinned analyzers (deadwood,
# dolly, arcleak), then the declared-dependency audit (Scripts/dependency-audit.sh) and the script, record and layering guards.
.ci/swift-ci run quality || fail "CI quality"

printf '==> build and test (release)\n'
# Explicit testability for optimized tests (ADR-0006). Benchmark/shipping binaries are built
# separately with `swift build -c release`; do not treat a testable build as byte-identical.
# --force-resolved-versions: build exactly what Package.resolved pins, and fail rather than re-resolve when it disagrees with the
# manifest, so a dependency's revision changes only in a reviewed commit.
swift test -c release --enable-testable-imports --force-resolved-versions

printf '\n[OK] clean\n'