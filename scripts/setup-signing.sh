#!/usr/bin/env bash
# One-time setup for maintainers: creates the two keys releases are signed with and stores
# them as GitHub Actions secrets. Run it on your own Mac; the private keys never leave it.
#
#   1. A self-signed code-signing certificate. Every build signed with it has the same
#      identity, so macOS keeps permissions such as Accessibility across updates.
#      (It is free and not an Apple Developer ID, so Gatekeeper still asks once on first
#      install.)
#   2. An Ed25519 key that signs updates, so the app only installs updates made by you.
#
# Usage: scripts/setup-signing.sh            (needs the GitHub CLI, `gh`, logged in)
#        scripts/setup-signing.sh --print    (prints the values to paste into GitHub instead)
#
# Run it only once: replacing the keys later means existing installs lose their
# Accessibility permission again and can no longer verify updates.
set -euo pipefail

REPO="${REPO:-haramrit09k/highlight-code}"
NAME="Highlight Code (self-signed)"
BACKUP="$HOME/HighlightCode-signing-backup"

if [[ -e "$BACKUP" ]]; then
  echo "$BACKUP already exists: the keys were created before. Delete it to start over." >&2
  exit 1
fi
mkdir -m 700 "$BACKUP"
cd "$BACKUP"

echo "==> Creating the code-signing certificate"
cat > cert.cnf <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config cert.cnf \
  -keyout signing-key.pem -out signing-cert.pem 2>/dev/null
P12_PASSWORD="$(openssl rand -base64 24)"
# OpenSSL 3 (e.g. Homebrew's) defaults to an encryption macOS's `security import` can't
# read; ask it for the legacy format. macOS's own LibreSSL already uses that format.
LEGACY=()
if openssl version | grep -q '^OpenSSL 3'; then LEGACY=(-legacy); fi
openssl pkcs12 -export "${LEGACY[@]}" -inkey signing-key.pem -in signing-cert.pem -name "$NAME" \
  -out signing.p12 -passout pass:"$P12_PASSWORD"
printf '%s' "$P12_PASSWORD" > signing-p12-password.txt
rm signing-key.pem cert.cnf

echo "==> Creating the update-signing key"
openssl rand 32 | base64 > sparkle-private-key.txt
chmod 600 ./*

P12_BASE64="$(base64 < signing.p12 | tr -d '\n')"
SPARKLE_KEY="$(tr -d '\n' < sparkle-private-key.txt)"

if [[ "${1:-}" == "--print" ]] || ! command -v gh >/dev/null; then
  cat <<EOF

Add these at https://github.com/$REPO/settings/secrets/actions ("New repository secret"):

  MACOS_SIGNING_P12            $P12_BASE64
  MACOS_SIGNING_P12_PASSWORD   $P12_PASSWORD
  SPARKLE_ED_PRIVATE_KEY       $SPARKLE_KEY
EOF
else
  echo "==> Storing them as GitHub Actions secrets in $REPO"
  printf '%s' "$P12_BASE64" | gh secret set MACOS_SIGNING_P12 --repo "$REPO"
  printf '%s' "$P12_PASSWORD" | gh secret set MACOS_SIGNING_P12_PASSWORD --repo "$REPO"
  printf '%s' "$SPARKLE_KEY" | gh secret set SPARKLE_ED_PRIVATE_KEY --repo "$REPO"
fi

cat <<EOF

Done. A backup is in $BACKUP.
Move it into a password manager (or another safe place) and delete the folder:
GitHub never shows secrets again, and without these keys future releases could not
update existing installs.
EOF
