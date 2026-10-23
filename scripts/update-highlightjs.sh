#!/usr/bin/env bash
# Rebuilds Resources/highlight.js from the official highlight.js browser build
# (the "common" language bundle plus a few extra languages useful to developers).
#
# Usage: scripts/update-highlightjs.sh [version]
set -euo pipefail

VERSION="${1:-11.11.1}"
EXTRA_LANGUAGES=(
  dockerfile scala dart elixir haskell powershell nginx protobuf latex clojure
  erlang ocaml groovy http julia matlab cmake fsharp x86asm armasm vim nix
)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

(cd "$WORK" && npm pack "@highlightjs/cdn-assets@${VERSION}" --silent >/dev/null && tar xzf ./*.tgz)
PKG="$WORK/package"

OUT="$ROOT/Resources/highlight.js"
{
  echo "/* highlight.js ${VERSION} (BSD-3-Clause, see Resources/highlight.js-LICENSE) */"
  cat "$PKG/highlight.min.js"
  echo
  for lang in "${EXTRA_LANGUAGES[@]}"; do
    cat "$PKG/languages/${lang}.min.js"
    echo
  done
} > "$OUT"
cp "$PKG/LICENSE" "$ROOT/Resources/highlight.js-LICENSE"

echo "Wrote $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes)"
