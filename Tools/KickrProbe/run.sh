#!/bin/bash
# Builds kickr-probe and runs it.
#
# macOS only hands out Bluetooth to a signed program that says why it wants it,
# and it will not read that from a bare command-line binary. So the tool is
# wrapped in the smallest possible app bundle, signed locally, and run from
# inside it. The first run puts up a permission prompt; say yes.
set -euo pipefail

cd "$(dirname "$0")/../.."
swift build --product kickr-probe

APP="$(pwd)/.build/KickrProbe.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/debug/kickr-probe "$APP/Contents/MacOS/kickr-probe"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>kickr-probe</string>
	<key>CFBundleIdentifier</key>
	<string>com.sbroenne.VirtualGears.KickrProbe</string>
	<key>CFBundleName</key>
	<string>KickrProbe</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>KickrProbe connects to a KICKR to measure how it responds.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1

LOG="${KICKR_PROBE_LOG:-/tmp/kickr-probe.log}"
: > "$LOG"

# Launched with `open` so the tool answers to macOS for itself. Started from a
# terminal instead, macOS judges the terminal, which never declared that it
# wants Bluetooth, and kills the tool the moment it asks for it.
open -n "$APP" --args "$@"

echo "Probing. Output also in $LOG. Press Control-C to stop."
tail -f "$LOG"
