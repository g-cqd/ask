#!/bin/sh
# Failures are seen (roadmap 0211): a scheduled run of WORKFLOW that failed opens one issue for it, or comments on the open one; a
# green run closes it. Run in CI with GH_TOKEN and GH_REPO set, after the workflow's jobs.
#
#   Scripts/ci-failure-issue.sh WORKFLOW failure|success RUN_URL
set -eu
workflow="$1"
outcome="$2"
url="$3"
title="Scheduled run of $workflow fails"
number=$(gh issue list --state open --search "\"$title\" in:title" --json number,title \
    --jq ".[] | select(.title == \"$title\") | .number" | head -1)
if [ "$outcome" = failure ]; then
    if [ -n "$number" ]; then
        gh issue comment "$number" --body "Failed again: $url"
    else
        gh issue create --title "$title" --body "The scheduled run failed: $url

This issue stays open while it fails, and the next green scheduled run closes it (roadmap 0211)."
    fi
elif [ -n "$number" ]; then
    gh issue close "$number" --comment "Green again: $url"
fi
