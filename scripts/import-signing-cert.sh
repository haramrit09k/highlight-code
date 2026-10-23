#!/usr/bin/env bash
# CI only: imports the self-signed code-signing certificate from the MACOS_SIGNING_P12 and
# MACOS_SIGNING_P12_PASSWORD secrets into a temporary keychain, and exports SIGN_IDENTITY
# (its SHA-1 hash) for scripts/build-app.sh. See scripts/setup-signing.sh.
set -euo pipefail

: "${MACOS_SIGNING_P12:?}" "${MACOS_SIGNING_P12_PASSWORD:?}"
TEMP="${RUNNER_TEMP:-$(mktemp -d)}"
KEYCHAIN="$TEMP/signing.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -base64 24)"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

printf '%s' "$MACOS_SIGNING_P12" | base64 --decode > "$TEMP/signing.p12"
security import "$TEMP/signing.p12" -k "$KEYCHAIN" -P "$MACOS_SIGNING_P12_PASSWORD" -T /usr/bin/codesign
rm -f "$TEMP/signing.p12"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
# shellcheck disable=SC2046
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')

# Self-signed, so not "valid" in the trust sense: look it up without -v, by hash.
IDENTITY="$(security find-identity -p codesigning "$KEYCHAIN" | awk '/Highlight Code/ { print $2; exit }')"
if [[ -z "$IDENTITY" ]]; then
  echo "No code-signing identity found in the imported certificate." >&2
  security find-identity -p codesigning "$KEYCHAIN" >&2
  exit 1
fi
echo "Signing identity: $IDENTITY"
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "SIGN_IDENTITY=$IDENTITY" >> "$GITHUB_ENV"
fi
