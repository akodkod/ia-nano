#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
CONFIGURATION="${1:-release}"
swift build -c "$CONFIGURATION" >&2
BUILD_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP="$ROOT_DIR/dist/iA Nano.app"
if [ -x "$APP/Contents/MacOS/ia-nano-gui" ]; then
    "$APP/Contents/MacOS/ia-nano" --quit-if-idle
elif /bin/ps -axww -o command= | /usr/bin/awk -v exe="$APP/Contents/MacOS/ia-nano" '$0 == exe || index($0, exe " ") == 1 { found=1 } END { exit !found }'; then
    echo "Close development editors before rebuilding the bundle." >&2
    exit 2
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/ia-nano" "$APP/Contents/MacOS/ia-nano"
cp "$BUILD_DIR/ia-nano-gui" "$APP/Contents/MacOS/ia-nano-gui"
# SwiftPM locates resource bundles beside the executable on macOS.
for resource in "$BUILD_DIR"/*.bundle; do
    [ ! -d "$resource" ] || cp -R "$resource" "$APP/Contents/MacOS/"
done
# Compile the editable Icon Composer source for modern and legacy macOS.
ICON_INFO="$BUILD_DIR/nano-icon-info.plist"
xcrun actool "$ROOT_DIR/Artwork/Nano.icon" \
    --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 \
    --app-icon Nano --output-partial-info-plist "$ICON_INFO" \
    --output-format human-readable-text >&2
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ia-nano-gui</string>
<key>LSUIElement</key><true/>
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
/usr/libexec/PlistBuddy -c "Merge '$ICON_INFO'" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP/Contents/MacOS/ia-nano" >&2
codesign --force --sign - "$APP/Contents/MacOS/ia-nano-gui" >&2
codesign --force --sign - "$APP" >&2
printf '%s\n' "$APP"
