#!/bin/bash
# Makes a self-signed code-signing certificate and puts it in a keychain file of its own.
#
#   scripts/cert.sh [name]    name defaults to dev
#
# Files land in ${CERT_DIR:-~/.local/share/appswap/cert}/<name>/. The login keychain and the
# keychain search list stay as they were, and nothing marks the certificate trusted, so this
# Mac judges the signature the way any other Mac will.
#
# macOS ties an Accessibility grant to the certificate. Replacing one voids every grant made
# to builds signed with it, so the script refuses to overwrite.
set -euo pipefail

ROOT="$(cd "$(/usr/bin/dirname "$0")/.." && pwd)"
NAME="${1:-dev}"
DIR="${CERT_DIR:-$HOME/.local/share/appswap/cert}/$NAME"
KC="$DIR/appswap-$NAME.keychain-db"
ENV_FILE="${ENV_FILE:-$ROOT/.env}"
# LibreSSL, because macOS can't import the PKCS#12 files that OpenSSL 3 and later write by default.
SSL=/usr/bin/openssl

[ ! -e "$DIR" ] || { echo "error: $DIR exists, and a new certificate would void every grant made to the old one" >&2; exit 1; }
umask 077
/bin/mkdir -p "$DIR"

/bin/cat > "$DIR/cert.conf" <<EOF
[ req ]
distinguished_name = name
prompt = no
[ name ]
CN = appswap $NAME
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
$SSL req -x509 -newkey rsa:2048 -nodes -keyout "$DIR/key.pem" -out "$DIR/cert.pem" -days 7300 -sha256 -config "$DIR/cert.conf" -extensions ext 2>/dev/null
P12PW="$($SSL rand -hex 16)"
KCPW="$($SSL rand -hex 16)"
$SSL pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/cert.pem" -name "appswap $NAME" -out "$DIR/cert.p12" -passout "pass:$P12PW"
/bin/rm "$DIR/key.pem" "$DIR/cert.conf"
printf '%s' "$P12PW" > "$DIR/cert.p12.pw"
printf '%s' "$KCPW" > "$KC.pw"

BEFORE="$(/usr/bin/security list-keychains -d user)"
/usr/bin/security create-keychain -p "$KCPW" "$KC"
# No arguments means no lock on sleep and no lock timeout.
/usr/bin/security set-keychain-settings "$KC"
/usr/bin/security unlock-keychain -p "$KCPW" "$KC"
/usr/bin/security import "$DIR/cert.p12" -P "$P12PW" -A -T /usr/bin/codesign -t cert -f pkcs12 -k "$KC"
# Without this codesign stops to ask for the keychain password in a dialog.
/usr/bin/security set-key-partition-list -S apple-tool:,apple: -s -k "$KCPW" "$KC" >/dev/null
[ "$BEFORE" = "$(/usr/bin/security list-keychains -d user)" ] || echo "warning: the keychain search list changed. Check it with: security list-keychains -d user" >&2

SHA1="$($SSL x509 -in "$DIR/cert.pem" -noout -fingerprint -sha1 | /usr/bin/sed -e 's/.*=//' -e 's/://g')"
echo "certificate: appswap $NAME, SHA-1 $SHA1"
echo "keychain:    $KC"
echo "backup:      $DIR/cert.p12 (password in cert.p12.pw)"
if [ "$NAME" = dev ] && [ ! -e "$ENV_FILE" ]; then
	printf 'BUNDLE_ID=style.xero.appswap.dev\nSIGN_IDENTITY=%s\nSIGN_KEYCHAIN=%s\n' "$SHA1" "$KC" > "$ENV_FILE"
	echo "wrote $ENV_FILE, so scripts/bundle.sh now signs development builds with this certificate"
else
	echo "to sign with it: SIGN_IDENTITY=$SHA1 SIGN_KEYCHAIN=$KC"
fi
