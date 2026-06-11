#!/usr/bin/env bash
# Create a STABLE self-signed code-signing identity in the login keychain (once).
#
# Why: ad-hoc signing (`codesign -s -`) gives the app a NEW identity every rebuild, so macOS
# TCC permissions (Accessibility, Microphone) never persist — you'd re-grant them on every
# build. Signing with a stable cert keeps the app's Designated Requirement constant, so a
# grant sticks across rebuilds. Idempotent: does nothing if the identity already exists.
set -euo pipefail

CERT="Sidekit Local Signing"
if security find-certificate -c "$CERT" >/dev/null 2>&1; then
  echo "Signing identity '$CERT' already present."
  exit 0
fi

echo "Creating self-signed code-signing identity '$CERT'…"
TMP=$(mktemp -d)
cat > "$TMP/cfg.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Sidekit Local Signing
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 -nodes -config "$TMP/cfg.cnf" 2>/dev/null
# -legacy: macOS `security import` can't verify OpenSSL 3.x's default PKCS12 MAC.
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:st -name "$CERT" 2>/dev/null
security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db -P st -T /usr/bin/codesign
rm -rf "$TMP"
echo "Done. (First build may show a one-time keychain prompt — click 'Always Allow'.)"
