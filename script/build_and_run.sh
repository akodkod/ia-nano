#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-run}"
case "$MODE" in run|--verify|--debug|--logs|--telemetry) ;; *) echo "Usage: $0 [--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;; esac
APP="$("$ROOT_DIR/script/package.sh" debug)"
PID_FILE="$ROOT_DIR/.build/development.pid"
if [ "$MODE" = --debug ]; then exec lldb -- "$APP/Contents/MacOS/ia-nano-gui"; fi
/usr/bin/open -n "$APP"
sleep 1
pgrep -f "^$APP/Contents/MacOS/ia-nano-gui" | tail -1 > "$PID_FILE" || true
case "$MODE" in
    --verify) test -s "$PID_FILE" ;;
    --logs|--telemetry) exec /usr/bin/log stream --info --style compact --predicate 'process == "ia-nano-gui"' ;;
esac
