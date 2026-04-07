#!/bin/zsh

set -euo pipefail

IDENTITY_NAME="${1:-SpeechBar Local Code Sign 2026}"
KEYCHAIN_PATH="${HOME}/Library/Keychains/login.keychain-db"
TMP_DIR="$(mktemp -d /tmp/speechbar-signing.XXXXXX)"
P12_PASSWORD="speechbar-local-signing"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if security find-identity -v -p codesigning | grep -F "\"$IDENTITY_NAME\"" >/dev/null; then
    echo "Signing identity already exists:"
    echo "  $IDENTITY_NAME"
    echo
    security find-identity -v -p codesigning | grep -F "\"$IDENTITY_NAME\""
    exit 0
fi

cat > "$TMP_DIR/codesign.cnf" <<EOF
[ req ]
default_bits = 2048
default_md = sha256
prompt = no
distinguished_name = dn
x509_extensions = v3_codesign

[ dn ]
CN = $IDENTITY_NAME
O = SlashVibe Local
OU = Development
C = CN

[ v3_codesign ]
basicConstraints = critical,CA:TRUE
keyUsage = critical,digitalSignature,keyCertSign,cRLSign
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

openssl req \
    -new \
    -newkey rsa:2048 \
    -nodes \
    -x509 \
    -days 3650 \
    -config "$TMP_DIR/codesign.cnf" \
    -keyout "$TMP_DIR/codesign.key" \
    -out "$TMP_DIR/codesign.crt" >/dev/null 2>&1

openssl pkcs12 \
    -export \
    -inkey "$TMP_DIR/codesign.key" \
    -in "$TMP_DIR/codesign.crt" \
    -out "$TMP_DIR/codesign.p12" \
    -name "$IDENTITY_NAME" \
    -passout "pass:$P12_PASSWORD" >/dev/null 2>&1

security import \
    "$TMP_DIR/codesign.p12" \
    -k "$KEYCHAIN_PATH" \
    -P "$P12_PASSWORD" \
    -f pkcs12 \
    -A >/dev/null

security add-trusted-cert \
    -r trustRoot \
    -k "$KEYCHAIN_PATH" \
    "$TMP_DIR/codesign.crt" >/dev/null

if ! security find-identity -v -p codesigning | grep -F "\"$IDENTITY_NAME\"" >/dev/null; then
    echo "Failed to create a usable signing identity: $IDENTITY_NAME" >&2
    exit 1
fi

echo "Created signing identity:"
echo "  $IDENTITY_NAME"
echo
security find-identity -v -p codesigning | grep -F "\"$IDENTITY_NAME\""
