#!/bin/bash
# Builds the SwiftPM product, wraps it in dist/<APP_NAME>.app, signs it, and checks the result.
#
# Settings come from the environment, then from an untracked .env beside Package.swift:
#   CONFIG         release (default) or debug
#   VERSION        CFBundleShortVersionString
#   BUILD_NUMBER   CFBundleVersion
#   BUNDLE_ID      CFBundleIdentifier
#   APP_NAME       the bundle's name
#   SIGN_IDENTITY  the certificate's 40-hex SHA-1, or - for an ad hoc signature
#   SIGN_KEYCHAIN  the keychain file that holds the identity
#
# Stays within bash 3.2 and calls system tools by absolute path, since GNU tools can come first on PATH.
set -euo pipefail

ROOT="$(cd "$(/usr/bin/dirname "$0")/.." && pwd)"
KEYS="CONFIG VERSION BUILD_NUMBER BUNDLE_ID APP_NAME SIGN_IDENTITY SIGN_KEYCHAIN"
if [ -f "$ROOT/.env" ]; then
	# Read as data, never sourced, and a value already in the environment wins.
	while IFS='=' read -r k v || [ -n "$k" ]; do
		case " $KEYS " in *" $k "*) [ -n "${!k+x}" ] || export "$k=$v" ;; esac
	done < "$ROOT/.env"
fi

fail() { echo "error: $*" >&2; exit 1; }

if [ -z "${BUNDLE_ID:-}" ] || [ -z "${SIGN_IDENTITY:-}" ]; then
	echo "warning: BUNDLE_ID or SIGN_IDENTITY is unset, so this is a throwaway build. An ad hoc signature loses its Accessibility grant on every rebuild." >&2
fi
CONFIG="${CONFIG:-release}"
VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_ID="${BUNDLE_ID:-style.xero.appswap.throwaway}"
APP_NAME="${APP_NAME:-appswap}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_KEYCHAIN="${SIGN_KEYCHAIN:-}"
case "$CONFIG" in release|debug) ;; *) fail "CONFIG is '$CONFIG', expected release or debug" ;; esac

EXE=appswap
APP="$ROOT/dist/$APP_NAME.app"
BIN="$APP/Contents/MacOS/$EXE"
WORK="$ROOT/.build/bundle"
SDK="$(/usr/bin/xcrun --sdk macosx --show-sdk-version)"
# Package.swift is the one place that names the deployment target.
MIN="$(/usr/bin/xcrun swift package --package-path "$ROOT" dump-package | /usr/bin/plutil -extract platforms.0.version raw -o - -)"
GIT="$(/usr/bin/git -C "$ROOT" rev-parse --verify --quiet --short HEAD || echo none)"

FLAGS=(--package-path "$ROOT" -c "$CONFIG" --arch arm64 --no-color-diagnostics)
# SwiftPM's linker records the deployment target as the SDK version, and AppKit then draws
# the controls of that older system. These flags record the SDK really used.
LINK=(-Xlinker -platform_version -Xlinker macos -Xlinker "$MIN" -Xlinker "$SDK")

echo "==> swift build -c $CONFIG"
/usr/bin/xcrun swift build "${FLAGS[@]}" "${LINK[@]}"
BUILT="$(/usr/bin/xcrun swift build "${FLAGS[@]}" --show-bin-path)/$EXE"
[ -x "$BUILT" ] || fail "no executable at $BUILT"

echo "==> assemble $APP"
/bin/rm -rf "$APP"
/bin/mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$WORK"
/bin/cp "$BUILT" "$BIN"

# Run paths left by the build point into this machine's toolchain.
/usr/bin/otool -l "$BIN" | /usr/bin/awk '$1 == "path" { print $2 }' | /usr/bin/sort -u | while read -r rpath; do
	[ "$rpath" = /usr/lib/swift ] || /usr/bin/xcrun install_name_tool -delete_rpath "$rpath" "$BIN" 2>/dev/null || true
done

PLIST="$APP/Contents/Info.plist"
/bin/cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AppSwapGitHash</key>
	<string>$GIT</string>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>$EXE</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$BUILD_NUMBER</string>
	<key>LSMinimumSystemVersion</key>
	<string>$MIN</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSSupportsAutomaticTermination</key>
	<false/>
	<key>NSSupportsSuddenTermination</key>
	<false/>
</dict>
</plist>
EOF
/usr/bin/plutil -lint "$PLIST" >/dev/null || fail "Info.plist doesn't parse"

ICNS="$WORK/AppIcon.icns"
if [ ! -f "$ICNS" ] || [ "$ROOT/scripts/icon.swift" -nt "$ICNS" ]; then
	echo "==> icon"
	SET="$WORK/AppIcon.iconset"
	/bin/rm -rf "$SET"
	/bin/mkdir -p "$SET"
	/usr/bin/xcrun --sdk macosx swiftc -O -o "$WORK/icon" "$ROOT/scripts/icon.swift"
	"$WORK/icon" "$WORK/icon.png"
	for size in 16 32 128 256 512; do
		/usr/bin/sips -z "$size" "$size" "$WORK/icon.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
		/usr/bin/sips -z "$((size * 2))" "$((size * 2))" "$WORK/icon.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
	done
	/usr/bin/iconutil --convert icns --output "$ICNS" "$SET"
fi
/bin/cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

SIGN=(--force --options runtime --timestamp=none --sign "$SIGN_IDENTITY")
if [ -n "$SIGN_KEYCHAIN" ]; then
	SIGN+=(--keychain "$SIGN_KEYCHAIN")
	# A keychain file locks at logout. cert.sh leaves its password beside it.
	[ ! -f "$SIGN_KEYCHAIN.pw" ] || /usr/bin/security unlock-keychain -p "$(/bin/cat "$SIGN_KEYCHAIN.pw")" "$SIGN_KEYCHAIN"
fi
if [ "$CONFIG" = debug ]; then
	# The hardened runtime refuses debuggers unless the signature carries this.
	/bin/cat > "$WORK/debug.entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.get-task-allow</key><true/></dict></plist>
EOF
	SIGN+=(--entitlements "$WORK/debug.entitlements")
fi
echo "==> sign ($([ "$SIGN_IDENTITY" = - ] && echo "ad hoc" || echo "$SIGN_IDENTITY"))"
/usr/bin/codesign "${SIGN[@]}" "$APP"

echo "==> check"
plist() { /usr/bin/plutil -extract "$1" raw -o - "$PLIST"; }
[ "$(plist LSUIElement)" = true ] || fail "LSUIElement isn't true"
[ "$(plist NSSupportsAutomaticTermination)" = false ] || fail "NSSupportsAutomaticTermination isn't false"
[ "$(plist NSSupportsSuddenTermination)" = false ] || fail "NSSupportsSuddenTermination isn't false"
[ "$(plist CFBundleIdentifier)" = "$BUNDLE_ID" ] || fail "the bundle id isn't $BUNDLE_ID"
/usr/bin/codesign --verify --deep --strict "$APP" || fail "the signature doesn't verify"
# Captured first, because a pipe into an early-exiting grep fails the pipeline under pipefail.
SIG="$(/usr/bin/codesign -dv "$APP" 2>&1)"
case "$SIG" in *flags=*runtime*) ;; *) fail "the signature lacks the hardened runtime" ;; esac
if [ "$SIGN_IDENTITY" != - ]; then
	DR="$(/usr/bin/codesign -d -r- "$APP" 2>/dev/null)"
	LEAF="$(echo "$SIGN_IDENTITY" | /usr/bin/tr 'A-F' 'a-f')"
	# A requirement that names the certificate survives a rebuild. One that holds a code hash doesn't.
	case "$DR" in *"certificate leaf = H\"$LEAF\""*) ;; *) fail "the designated requirement doesn't name the certificate: $DR" ;; esac
	case "$DR" in *cdhash*) fail "the designated requirement holds a code hash: $DR" ;; esac
fi
ARCHS="$(/usr/bin/xcrun lipo -archs "$BIN")"
[ "$ARCHS" = arm64 ] || fail "architectures are '$ARCHS', expected arm64"
RECORDED="$(/usr/bin/xcrun vtool -show-build "$BIN" | /usr/bin/awk '$1 == "sdk" { print $2 }')"
[ "$RECORDED" = "$SDK" ] || fail "the binary records SDK '$RECORDED', expected $SDK"
LIBS="$(/usr/bin/otool -L "$BIN")"
case "$LIBS" in *@rpath/*|*PrivateFrameworks*) fail "the binary links an @rpath or private library: $LIBS" ;; esac
# CGS[A-Z] leaves public names such as CGSizeZero alone.
if /usr/bin/xcrun nm -u "$BIN" | /usr/bin/grep -E '_SLPS|_SLS[A-Z]|_CGS[A-Z]|_AXUIElementGetWindow|_CGEventTapCreate'; then
	fail "the binary links a private symbol or an event tap"
fi

echo "ok: $APP ($BUNDLE_ID $VERSION build $BUILD_NUMBER, $CONFIG, git $GIT, macOS $MIN, SDK $SDK)"
