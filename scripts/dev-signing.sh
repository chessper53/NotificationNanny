#!/usr/bin/env bash
# Create a stable development identity to preserve macOS permissions across rebuilds.
# Use a separate keychain and restore the user's search list; see docs/DEBUGGING.md.
set -euo pipefail
cd "$(dirname "$0")/.."
DIR="$PWD/build/dev-signing"
KC="$DIR/dev.keychain-db"
PASS=notificationnanny-dev
NAME="NotificationNanny Dev"
[[ -f "$KC" ]] && exit 0

mkdir -p "$DIR"
# The system's LibreSSL: its .p12 is one `security import` reads.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$NAME" \
    -keyout "$DIR/key.pem" -out "$DIR/cert.pem" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/cert.pem" -out "$DIR/id.p12" -passout "pass:$PASS"

# Keychain creation changes the search list; restore the original entries.
saved=()
while IFS= read -r line; do saved+=("$(echo "$line" | tr -d '"' | xargs)"); done < <(security list-keychains -d user)
security create-keychain -p "$PASS" "$KC"
security list-keychains -d user -s "${saved[@]}"
# No locking after a while, so a build never stops to ask.
security set-keychain-settings "$KC"
security unlock-keychain -p "$PASS" "$KC"
security import "$DIR/id.p12" -k "$KC" -P "$PASS" -T /usr/bin/codesign >/dev/null
# codesign may use the key without asking.
security set-key-partition-list -S apple-tool:,apple: -s -k "$PASS" "$KC" >/dev/null
rm -f "$DIR/key.pem" "$DIR/id.p12"
# Select by the unique certificate hash; macOS needs a stable identity, even if it is self signed.
security find-identity -p codesigning "$KC" | awk '/NotificationNanny Dev/ { print $2; exit }' > "$DIR/identity"
[[ -s "$DIR/identity" ]] || { echo "No identity in $KC" >&2; exit 1; }
echo "Dev signing identity \"$NAME\" ($(cat "$DIR/identity")) in $KC"
