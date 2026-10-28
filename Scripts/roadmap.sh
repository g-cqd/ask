#!/bin/sh
# The roadmap as a table, read from each entry's front matter, so there is no second copy to drift.
#
#   Scripts/roadmap.sh            every entry
#   Scripts/roadmap.sh open       only entries that are not done
set -eu
cd "$(dirname "$0")/.."
only=${1:-all}
printf '%-5s %-12s %-18s %s\n' entry status blocked-by title
for file in development/roadmap/*.md; do
    status=$(sed -n 's/^status: *//p' "$file" | head -1)
    [ "$only" = "open" ] && [ "$status" = "done" ] && continue
    blocked=$(sed -n 's/^blocked-by: *//p' "$file" | head -1 | tr -d '[]" ')
    title=$(sed -n 's/^# [0-9]* — //p' "$file" | head -1)
    printf '%-5s %-12s %-18s %s\n' "$(basename "$file" | cut -c1-4)" "$status" "${blocked:--}" "$title"
done
