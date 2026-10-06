#!/bin/bash
# One-time: a self-signed code-signing identity "Video Prompt Dev" in the login keychain, so
# rebuilt dev apps keep the same signature and macOS keeps their permission grants.
set -euo pipefail
NAME="Video Prompt Dev"
if security find-identity -p codesigning | grep -q "\"$NAME\""; then echo "already have $NAME"; exit 0; fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cfg" <<CFG
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CFG
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cfg" 2>/dev/null
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:vpdev 2>/dev/null \
  || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:vpdev
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P vpdev -T /usr/bin/codesign
if security find-identity -p codesigning | grep -q "\"$NAME\""; then echo "created $NAME"; exit 0; fi
cp "$TMP/cert.pem" "$HOME/.video-prompt-dev-cert.pem"
echo "Imported, but macOS doesn't trust it for code signing yet. Run this once (asks for your password):"
echo "  security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db ~/.video-prompt-dev-cert.pem"
