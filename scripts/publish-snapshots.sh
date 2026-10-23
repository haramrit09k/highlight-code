#!/usr/bin/env bash
# Commits the smoke test's snapshots (as small JPEGs) to the pr-assets branch, which is
# never merged, so pull requests can show screenshots without bloating main.
#
# Usage: scripts/publish-snapshots.sh <folder>      e.g. scripts/publish-snapshots.sh pr-1
set -euo pipefail

DIR="${1:?folder name required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS="${RUNNER_TEMP:-$(mktemp -d)}/pr-assets"

cd "$ROOT"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

rm -rf "$ASSETS"
if git fetch --depth=1 origin pr-assets; then
  git worktree add --force -B pr-assets "$ASSETS" FETCH_HEAD
else
  git worktree add --orphan -b pr-assets "$ASSETS"
fi

mkdir -p "$ASSETS/$DIR"
for f in build/smoke/snapshots/*.png; do
  sips -Z 1200 -s format jpeg -s formatOptions 82 "$f" \
    --out "$ASSETS/$DIR/$(basename "$f" .png).jpg" >/dev/null
done

git -C "$ASSETS" add "$DIR"
if git -C "$ASSETS" diff --cached --quiet; then
  echo "::notice title=pr-assets::Snapshots unchanged"
  exit 0
fi
git -C "$ASSETS" commit -m "Screenshots for $DIR from run ${GITHUB_RUN_ID:-local}"
git -C "$ASSETS" push origin pr-assets
echo "::notice title=pr-assets::$(git -C "$ASSETS" rev-parse HEAD)"
