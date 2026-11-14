#!/usr/bin/env bash
# Creates a self-signed code-signing identity "Flow Local Code Signing" in the login keychain,
# so scripts/build_app.sh can sign Flow with the same identity on every build.
#
# What it changes: adds one private key + certificate to your login keychain, usable by
# /usr/bin/codesign without a prompt. It does NOT mark the certificate as trusted or
# change any system trust or security settings. It is for local development only.
#
# Remove it later with:
#   security delete-identity -c "Flow Local Code Signing" ~/Library/Keychains/login.keychain-db
set -euo pipefail

NAME="Flow Local Code Signing"
# System LibreSSL: its PKCS#12 encryption is readable by `security import` (OpenSSL 3 defaults are not).
OPENSSL=/usr/bin/openssl
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
  echo "Identity \"$NAME\" already exists; nothing to do."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.conf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.conf" 2>/dev/null
# Random throwaway passphrase: only protects the temporary .p12 file.
PASS="$("$OPENSSL" rand -hex 16)"
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$NAME" -out "$WORK/identity.p12" -passout "pass:$PASS"

# -T lets codesign use the key without a keychain access prompt.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null

echo "Created \"$NAME\":"
security find-identity -p codesigning | grep "\"$NAME\""
