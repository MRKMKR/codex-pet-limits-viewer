# Codex Pet Limits Viewer

Simple macOS helper that shows your Codex 5-hour and weekly usage limits when you hover over your Codex pet.

It is intentionally quiet: no persistent rings, no dashboard, and no controls on top of the pet. The popover is click-through and hides while you drag the pet.

![MIT license](https://img.shields.io/badge/license-MIT-blue.svg)

## Status

Experimental. This is not an official OpenAI or Codex feature.

The helper reads local Codex desktop state and an internal ChatGPT usage endpoint. Codex or ChatGPT updates may change those shapes and require a fix.

## What It Shows

```text
Codex Limits
5h    79% left    resets 16:00
Week  95% left    resets 23:39
Live - refreshed 13:45
```

If the live endpoint cannot be read, the helper tries to fall back to cached Codex rate-limit events from the local Codex log database. If neither source is available, it shows `unavailable`.

## Requirements

- macOS
- Codex desktop app with Codex Pets enabled
- Swift toolchain / Xcode command line tools

Check Swift with:

```bash
swift --version
```

## Install

Clone and install:

```bash
git clone https://github.com/MRKMKR/codex-pet-limits-viewer.git
cd codex-pet-limits-viewer
./install.sh
```

The installer:

- builds the release binary
- installs it to `~/.codex/tools/codex-pet-limits-viewer/`
- creates `~/Library/LaunchAgents/com.codex-pet-limits-viewer.plist`
- starts it immediately
- starts it again at login

## Test The Readout

```bash
~/.codex/tools/codex-pet-limits-viewer/codex-pet-limits-viewer --once
```

Diagnostic screen/position output:

```bash
~/.codex/tools/codex-pet-limits-viewer/codex-pet-limits-viewer --diagnose
```

## Uninstall

From the repo:

```bash
./uninstall.sh
```

Or remove manually:

```bash
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.codex-pet-limits-viewer.plist" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.codex-pet-limits-viewer.plist"
rm -rf "$HOME/.codex/tools/codex-pet-limits-viewer"
```

## Privacy

This helper is read-only. It does not write to Codex runtime files and does not send telemetry.

It reads:

- `~/.codex/.codex-global-state.json` to locate the Codex pet
- `~/.codex/auth.json` to read the local access token used for the live usage request
- `~/.codex/logs_2.sqlite` for cached rate-limit events if the live request fails

It contacts:

- `https://chatgpt.com/backend-api/wham/usage`

It does not store your token. Local logs from this helper go under:

```text
~/.codex/tools/codex-pet-limits-viewer/
```

## Development

Run tests:

```bash
swift test
```

Build:

```bash
swift build -c release
```

Run from the build output:

```bash
.build/release/codex-pet-limits-viewer --once
```

## License

MIT
