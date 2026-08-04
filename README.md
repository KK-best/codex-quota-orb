# Codex Quota Orb

A small native macOS menu-bar-free floating orb for monitoring Codex usage.

## What it does

- Shows the current Codex quota and reset time in a compact floating orb.
- Displays 24-hour and 48-hour reset forecasts from `codex-reset.com`.
- Aggregates local Codex token usage by project and conversation.
- Generates short conversation labels locally, without an extra model call.
- Refreshes reset forecasts silently every five minutes.

## Privacy

This app is designed for local use. It reads the local Codex app-server responses
and local Codex usage databases in read-only mode. It does not upload local
conversation content, credentials, account tokens, databases, logs, or screenshots.

The public repository contains only source code, tests, build scripts, and
documentation. No local app bundle, database, cache, or machine-specific path is
committed.

The reset forecast is fetched from the public endpoint
`https://codex-reset.com/api/reset-poll`.

## Requirements

- macOS 14 or later
- Swift 5.10 or later
- A local Codex installation and an active Codex session for live quota data

## Build

```bash
./scripts/build_app.sh
open "dist/Codex 额度球.app"
```

The build script creates a signed-for-local-use app bundle in `dist/`.

## Test

```bash
swift test --disable-sandbox
```

## License

MIT. See [LICENSE](LICENSE).
