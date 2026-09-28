#!/bin/bash
#
# Prints the release notes for a version tag as Markdown: install steps, then
# every commit since the previous release. GitHub's generated notes only list
# merged pull requests, and Drydock is committed to directly, so they'd be
# empty.
#
# Usage:
#   Tools/release-notes.sh v1.2.3

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: Tools/release-notes.sh <tag>" >&2
    exit 1
fi

TAG="$1"
VERSION="${TAG#v}"

# Nearest tag before this one; empty for the first release.
PREVIOUS_TAG="$(git describe --tags --abbrev=0 "$TAG^" 2> /dev/null || true)"

REPOSITORY_URL="$(git remote get-url origin \
    | sed -E -e 's#^git@github\.com:#https://github.com/#' -e 's#\.git$##')"

if [[ -n "$PREVIOUS_TAG" ]]; then
    COMMIT_RANGE="$PREVIOUS_TAG..$TAG"
else
    COMMIT_RANGE="$TAG"
fi

cat << EOF
## Install

1. Download **Drydock-$VERSION.dmg** below.
2. Open it and drag **Drydock** into **Applications**.
3. Open Drydock and choose your EV Nova folder (the one containing \`Nova Files\`).

Requires macOS 14 (Sonoma) or newer.

## What's changed

EOF

git log --no-merges --format='- %s (%h)' "$COMMIT_RANGE"

if [[ -n "$PREVIOUS_TAG" ]]; then
    echo
    echo "**Full changelog**: $REPOSITORY_URL/compare/$PREVIOUS_TAG...$TAG"
fi
