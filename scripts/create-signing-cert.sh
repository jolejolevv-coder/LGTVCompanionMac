#!/bin/bash
#
# Creates a self-signed code signing certificate in the login keychain.
# Run once per Mac. Usage: ./scripts/create-signing-cert.sh
#
# Why: macOS ties the Accessibility and System Audio permissions to the app's
# code signature. An ad-hoc signature changes with every build, so every
# update silently invalidated both grants. Signing every build with the same
# certificate keeps the signature identity stable and the grants valid.
#
# The certificate is not trusted by anyone else and is useless for
# distribution. It only gives this Mac a stable identity for local builds.
#
set -euo pipefail

IDENTITY="${LGTV_SIGN_IDENTITY:-LGTV Companion Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
VALID_DAYS=3650

if security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$IDENTITY\""; then
    echo "Signing identity \"$IDENTITY\" already exists. Nothing to do."
    exit 0
fi

WORK="$(mktemp -d)"
# The private key must not outlive this script outside the keychain.
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.conf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONF

# /usr/bin/openssl (LibreSSL) writes a PKCS#12 format that `security import`
# can read. Homebrew's OpenSSL 3 defaults to one it cannot.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days "$VALID_DAYS" \
    -config "$WORK/cert.conf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

# Throwaway password, only protects the temporary .p12 during import.
P12_PASSWORD="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -name "$IDENTITY" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/identity.p12" -passout "pass:$P12_PASSWORD"

security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign

echo "Created signing identity \"$IDENTITY\"."
echo "The first build will ask to use the key: choose \"Always Allow\"."
