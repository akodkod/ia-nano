# Shared paths and checks for install.sh and uninstall.sh.
INSTALL_ROOT="${IA_NANO_INSTALL_ROOT:-$HOME}"
case "$INSTALL_ROOT" in
    /*) ;;
    *) echo 'iA Nano: installation root must be an absolute path.' >&2; exit 2 ;;
esac
INSTALL_ROOT="${INSTALL_ROOT%/}"
if [ -z "$INSTALL_ROOT" ]; then
    echo 'iA Nano: refusing to install or uninstall at the filesystem root.' >&2
    exit 2
fi
APP_DEST="$INSTALL_ROOT/Applications/iA Nano.app"
LAUNCHER_DEST="$INSTALL_ROOT/.local/bin/ia-nano"

check_destinations() {
    if [ -e "$APP_DEST" ] || [ -L "$APP_DEST" ]; then
        if [ -L "$APP_DEST" ] || [ ! -d "$APP_DEST" ] ||
            [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DEST/Contents/Info.plist" 2>/dev/null || true)" != app.ianano.editor ]; then
            echo "iA Nano: refusing to change an unrecognized app at $APP_DEST" >&2
            exit 2
        fi
    fi
    if [ -e "$LAUNCHER_DEST" ] || [ -L "$LAUNCHER_DEST" ]; then
        if [ ! -f "$LAUNCHER_DEST" ] || ! grep -Fq 'exec "$APP/Contents/MacOS/ia-nano" "$@"' "$LAUNCHER_DEST"; then
            echo "iA Nano: refusing to change an unrecognized launcher at $LAUNCHER_DEST" >&2
            exit 2
        fi
    fi
    if [ -x "$APP_DEST/Contents/MacOS/ia-nano-gui" ]; then
        "$APP_DEST/Contents/MacOS/ia-nano" --quit-if-idle
        return
    fi
    # Older installations have no resident-host control command.
    local processes
    processes="$(/bin/ps -axww -o command=)"
    if printf '%s\n' "$processes" | /usr/bin/awk -v executable="$APP_DEST/Contents/MacOS/ia-nano" '
        $0 == executable || index($0, executable " ") == 1 { found = 1 }
        END { exit !found }
    '; then
        echo 'iA Nano: close installed editor sessions before installing or uninstalling.' >&2
        exit 2
    fi
}
