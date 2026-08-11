#!/bin/bash
# Shared plumbing for the hardware tools. Each tool's run.sh sets a few
# variables and sources this.
#
# macOS only hands out Bluetooth to a signed program that says why it wants it,
# and it will not read that from a bare command-line binary. So every tool is
# wrapped in the smallest possible app bundle and run from inside it.
#
# The bundle is signed with the Apple Development certificate rather than
# ad-hoc. An ad-hoc signature has no stable identity, so macOS falls back to
# matching the binary itself and every rebuild looks like a brand new program
# that has never been trusted. A real certificate gives the bundle an identity
# that survives rebuilding: measured here by granting permission once, then
# recompiling and running again without being asked a second time.
#
# The identifier deliberately differs from the ones the ad-hoc bundles used.
# Changing the signature of an identifier macOS already has a record for makes
# it refuse quietly instead of asking again, and that record cannot be cleared
# with tccutil.
#
# Callers must set:
#   PRODUCT      the swift build product name, e.g. ride-sim
#   BUNDLE       the bundle name, e.g. RideSim
#   DESCRIPTION  why the tool wants Bluetooth, shown in the permission prompt
# and may set:
#   SENTINEL     a line the tool prints when it is done, so following the log
#                stops by itself instead of hanging until interrupted
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

swift build --product "$PRODUCT"

APP="$REPO_ROOT/.build/$BUNDLE.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/debug/$PRODUCT" "$APP/Contents/MacOS/$PRODUCT"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>$PRODUCT</string>
	<key>CFBundleIdentifier</key>
	<string>com.sbroenne.VirtualGearsTools.$BUNDLE</string>
	<key>CFBundleName</key>
	<string>$BUNDLE</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>$DESCRIPTION</string>
</dict>
</plist>
PLIST

# Prefer a real certificate so the permission sticks. Ad-hoc still works if
# there is no certificate on this machine; it just asks every time.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
	| grep "Apple Development" | head -1 | sed 's/.*"\(.*\)"/\1/')"
if [ -n "$IDENTITY" ]; then
	codesign --force --sign "$IDENTITY" \
		--identifier "com.sbroenne.VirtualGearsTools.$BUNDLE" "$APP" >/dev/null 2>&1
else
	echo "No Apple Development certificate found; signing ad-hoc." >&2
	echo "macOS will ask for Bluetooth permission after every rebuild." >&2
	codesign --force --sign - "$APP" >/dev/null 2>&1
fi

# ride-sim -> RIDE_SIM_LOG
LOG_VARIABLE="$(echo "$PRODUCT" | tr 'a-z-' 'A-Z_')_LOG"
LOG="${!LOG_VARIABLE:-/tmp/$PRODUCT.log}"
: > "$LOG"

# Launched with `open` so the tool answers to macOS for itself. Started from a
# terminal instead, macOS judges the terminal, which never declared that it
# wants Bluetooth, and kills the tool the moment it asks for it.
open -n "$APP" --args "$@"

echo "Running. Output also in $LOG."
if [ -n "${SENTINEL:-}" ]; then
	# `tail -f | sed /q` is not enough on its own: sed quits at the sentinel but
	# tail sits waiting for a write that never comes, so the script hangs on a
	# finished tool. Follow the file directly and stop the moment we see it.
	shown=0
	while true; do
		total="$(wc -l < "$LOG")"
		if [ "$total" -gt "$shown" ]; then
			tail -n "+$((shown + 1))" "$LOG" | head -n "$((total - shown))"
			shown="$total"
			if tail -n 1 "$LOG" | grep -q "^$SENTINEL"; then
				break
			fi
		fi
		sleep 0.5
	done
else
	echo "Press Control-C to stop."
	tail -f "$LOG"
fi
