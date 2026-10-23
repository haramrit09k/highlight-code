#!/usr/bin/env bash
# Helpers for the Sparkle update-signing key.
#
# The key is stored (in the SPARKLE_ED_PRIVATE_KEY secret) as base64 of 32 random bytes,
# which is all an Ed25519 private key is. This turns it into what OpenSSL and Sparkle need.
#
#   scripts/sparkle-key.sh public           # prints the base64 public key (SUPublicEDKey)
#   scripts/sparkle-key.sh sign <file>      # prints the file's base64 EdDSA signature
#
# Reads the private key from $SPARKLE_ED_PRIVATE_KEY. Needs OpenSSL 3 (not macOS's LibreSSL).
set -euo pipefail

: "${SPARKLE_ED_PRIVATE_KEY:?SPARKLE_ED_PRIVATE_KEY is not set}"

OPENSSL="${OPENSSL:-}"
if [[ -z "$OPENSSL" ]]; then
  if command -v brew >/dev/null && [[ -x "$(brew --prefix openssl@3 2>/dev/null)/bin/openssl" ]]; then
    OPENSSL="$(brew --prefix openssl@3)/bin/openssl"
  else
    OPENSSL=openssl
  fi
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
chmod 700 "$WORK"

# PKCS#8 DER for an Ed25519 key is a fixed 16-byte header followed by the 32-byte seed.
{
  printf '\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x70\x04\x22\x04\x20'
  printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | base64 --decode
} > "$WORK/key.der"
"$OPENSSL" pkey -inform DER -in "$WORK/key.der" -out "$WORK/key.pem"

case "${1:-}" in
  public)
    "$OPENSSL" pkey -in "$WORK/key.pem" -pubout -outform DER | tail -c 32 | base64
    ;;
  sign)
    "$OPENSSL" pkeyutl -sign -inkey "$WORK/key.pem" -rawin -in "${2:?file to sign}" | base64 | tr -d '\n'
    echo
    ;;
  *)
    echo "usage: $0 public | sign <file>" >&2
    exit 2
    ;;
esac
