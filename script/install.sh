#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/install-common.sh"
APP_SOURCE="$ROOT_DIR/dist/iA Nano.app"
if [ ! -x "$APP_SOURCE/Contents/MacOS/ia-nano" ] ||
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_SOURCE/Contents/Info.plist" 2>/dev/null || true)" != app.ianano.editor ]; then
    echo 'iA Nano: build the app first with ./script/package.sh.' >&2
    exit 2
fi
check_destinations
mkdir -p "$INSTALL_ROOT/Applications" "$INSTALL_ROOT/.local/bin"
STAGING="$(mktemp -d "$INSTALL_ROOT/Applications/.ia-nano-install.XXXXXX")"
LAUNCHER_TEMP=''
APP_REPLACED=false
COMPLETED=false
cleanup() {
    local status=$?
    if [ "$COMPLETED" = false ]; then
        if [ "$APP_REPLACED" = true ]; then rm -rf -- "$APP_DEST"; fi
        if [ -d "$STAGING/previous.app" ]; then mv -- "$STAGING/previous.app" "$APP_DEST"; fi
    fi
    [ -z "$LAUNCHER_TEMP" ] || rm -f -- "$LAUNCHER_TEMP"
    rm -rf -- "$STAGING"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Stage a complete replacement so updates cannot retain obsolete bundle files.
/usr/bin/ditto "$APP_SOURCE" "$STAGING/iA Nano.app"
LAUNCHER_TEMP="$(mktemp "$INSTALL_ROOT/.local/bin/.ia-nano-install.XXXXXX")"
cp "$ROOT_DIR/bin/ia-nano" "$LAUNCHER_TEMP"
chmod 755 "$LAUNCHER_TEMP"
if [ -d "$APP_DEST" ]; then mv -- "$APP_DEST" "$STAGING/previous.app"; fi
mv -- "$STAGING/iA Nano.app" "$APP_DEST"
APP_REPLACED=true
mv -f -- "$LAUNCHER_TEMP" "$LAUNCHER_DEST"
COMPLETED=true
printf 'Installed %s\nLauncher: %s\nSee README.md for zsh or fish configuration.\n' "$APP_DEST" "$LAUNCHER_DEST"
