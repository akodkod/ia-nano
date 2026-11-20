#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/install-common.sh"
check_destinations
# These exact destinations are validated before either is removed.
rm -rf -- "$APP_DEST"
rm -f -- "$LAUNCHER_DEST"
printf '%s\n' 'Uninstalled iA Nano (or it was already absent).' \
    'Your documents, accent preference, and shell configuration were left intact.' \
    'Remove the iA Nano environment-variable lines from your shell config if no longer needed.'
