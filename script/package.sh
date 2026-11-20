#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
CONFIGURATION="${1:-release}"
swift build -c "$CONFIGURATION" >&2
BUILD_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP="$ROOT_DIR/dist/iA Nano.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/ia-nano" "$APP/Contents/MacOS/ia-nano"
# SwiftPM locates resource bundles beside the executable on macOS.
for resource in "$BUILD_DIR"/*.bundle; do
    [ ! -d "$resource" ] || cp -R "$resource" "$APP/Contents/MacOS/"
done
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ia-nano</string>
<key>CFBundleIdentifier</key><string>app.ianano.editor</string>
<key>CFBundleName</key><string>iA Nano</string>
<key>CFBundleDisplayName</key><string>iA Nano</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>iA Nano is an independent project, not affiliated with iA.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >&2
printf '%s\n' "$APP"
