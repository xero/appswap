#!/bin/bash
# Quits every running copy that shares the built bundle's id, then opens dist/<APP_NAME>.app.
# The APPSWAP_* switches reach the app through `open --env`, since `open` drops the shell's environment.
set -euo pipefail

ROOT="$(cd "$(/usr/bin/dirname "$0")/.." && pwd)"
APP="$ROOT/dist/${APP_NAME:-appswap}.app"
[ -d "$APP" ] || { echo "error: no bundle at $APP, run scripts/bundle.sh first" >&2; exit 1; }
ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$APP/Contents/Info.plist")"

# Matched by bundle id and not by name, so an installed release keeps running.
for pid in $(/usr/bin/pgrep -x appswap || true); do
	exe="$(/bin/ps -o comm= -p "$pid" || true)"
	plist="${exe%/MacOS/*}/Info.plist"
	[ -f "$plist" ] && [ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$plist")" = "$ID" ] || continue
	/bin/kill "$pid"
	while /bin/kill -0 "$pid" 2>/dev/null; do /bin/sleep 0.1; done
done

ENVS=()
for k in APPSWAP_PUBLIC_ONLY APPSWAP_NO_WINDOW_ID APPSWAP_NO_SPACES APPSWAP_NO_UNHIDE; do
	[ -z "${!k:-}" ] || ENVS+=(--env "$k=${!k}")
done
/usr/bin/open ${ENVS[@]+"${ENVS[@]}"} "$APP"
echo "opened $APP ($ID)"
