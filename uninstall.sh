#!/usr/bin/env bash
set -euo pipefail

LABEL="com.codex-pet-limits-viewer"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
INSTALL_DIR="$HOME/.codex/tools/codex-pet-limits-viewer"
UID_VALUE="$(id -u)"

launchctl bootout "gui/$UID_VALUE" "$PLIST" >/dev/null 2>&1 || true
pkill -f "$INSTALL_DIR/codex-pet-limits-viewer" >/dev/null 2>&1 || true
rm -f "$PLIST"
rm -rf "$INSTALL_DIR"

echo "Uninstalled codex-pet-limits-viewer."
