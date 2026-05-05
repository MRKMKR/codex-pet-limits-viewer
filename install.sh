#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "codex-pet-limits-viewer only supports macOS." >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift is required. Install Xcode command line tools, then retry." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.codex/tools/codex-pet-limits-viewer"
BIN="$INSTALL_DIR/codex-pet-limits-viewer"
LABEL="com.codex-pet-limits-viewer"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_VALUE="$(id -u)"

cd "$ROOT"
swift build -c release

mkdir -p "$INSTALL_DIR"
cp "$ROOT/.build/release/codex-pet-limits-viewer" "$BIN"
chmod 755 "$BIN"

mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$INSTALL_DIR/logs"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BIN</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>$INSTALL_DIR/logs/stdout.log</string>
  <key>StandardErrorPath</key>
  <string>$INSTALL_DIR/logs/stderr.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
</dict>
</plist>
PLIST

launchctl bootout "gui/$UID_VALUE" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID_VALUE" "$PLIST"
launchctl kickstart -k "gui/$UID_VALUE/$LABEL"

echo "Installed codex-pet-limits-viewer."
echo "Hover over your Codex pet to see limits."
echo "Run '$BIN --once' to test the usage readout."
