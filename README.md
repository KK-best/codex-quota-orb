# Codex Quota Orb

> A native macOS floating orb for monitoring Codex quota, reset forecasts, local token usage, and API-equivalent cost.

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111827?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Swift 5.10+](https://img.shields.io/badge/Swift-5.10%2B-F05138?style=flat-square&logo=swift)](https://www.swift.org/)
[![License: MIT](https://img.shields.io/badge/license-MIT-2563EB?style=flat-square)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/KK-best/codex-quota-orb?style=flat-square)](https://github.com/KK-best/codex-quota-orb/stargazers)

**[Download the latest macOS build](https://github.com/KK-best/codex-quota-orb/releases/latest/download/Codex-Quota-Orb-macOS.zip)** · [View the source](https://github.com/KK-best/codex-quota-orb) · [Report a problem](https://github.com/KK-best/codex-quota-orb/issues)

中文：把 Codex 的额度、重置概率、项目/对话 Token 消耗和 API 等价成本，放到桌面右侧一个轻量的小球里。

## What this is

**Codex Quota Orb** is a small, native, local-first macOS utility. It stays out of the menu bar, floats above your work, and opens a focused dashboard only when you need detail.

If you searched for **Codex quota monitor**, **Codex token usage tracker**, **Codex reset probability**, or **Codex API cost estimator for macOS**, this is the canonical repository and download page.

### At a glance

| Need | What the orb shows |
| --- | --- |
| Avoid quota surprises | Current remaining quota, window and reset time |
| Plan the next session | Separate 24h and 48h reset-probability orbs |
| Find the expensive work | Project and conversation-level Token usage |
| Translate usage into money | API-equivalent cost estimate, with pricing caveats |

## Features

- **Native floating orb** — compact macOS UI, draggable, always available, and clean around the transparent edge.
- **Quota refresh animation** — hover the main orb to see the ring read from 100% down to the current value.
- **Configurable forecast orbs** — show both 24h/48h forecasts, only one, or hide both from Settings.
- **Silent refresh** — quota and reset forecasts update every five minutes without opening a browser window.
- **Local project and conversation usage** — groups local Codex activity and keeps the conversation labels short and readable.
- **API-equivalent cost mode** — compares observed Token usage with public API pricing; it is an estimate, not a billing statement.
- **Privacy-first by default** — local reads only; no cloud sync, analytics SDK, or extra model call for labels.

## Download and run in 30 seconds

1. Download **[Codex-Quota-Orb-macOS.zip](https://github.com/KK-best/codex-quota-orb/releases/latest/download/Codex-Quota-Orb-macOS.zip)**.
2. Unzip it and move **Codex 额度球.app** to Applications (optional).
3. Open the app. The first launch may require **right-click → Open** because the build is signed for local use rather than notarized by Apple.

The live quota view needs a local Codex installation and an active Codex session. The 24h/48h forecast orbs use the public [codex-reset.com](https://codex-reset.com/) endpoint.

## Build from source

~~~bash
git clone https://github.com/KK-best/codex-quota-orb.git
cd codex-quota-orb
./scripts/build_app.sh
open "dist/Codex 额度球.app"
~~~

Requirements: macOS 14 or later and Swift 5.10 or later.

Run the test suite with:

~~~bash
swift test --disable-sandbox
~~~

## Privacy and data boundaries

- Reads local Codex app-server responses and local Codex usage databases in **read-only** mode.
- Does not upload conversation content, credentials, account tokens, databases, logs, or screenshots.
- Conversation labels are generated locally without another model request.
- Reset forecasts come from the public endpoint https://codex-reset.com/api/reset-poll.
- API-equivalent cost is an analysis aid; actual plan limits and invoices remain authoritative.

## Settings

Open the dashboard and choose the gear button, or use the macOS **Settings…** menu:

- Show 24-hour reset probability
- Show 48-hour reset probability

The floating panel automatically tightens its height when a forecast orb is hidden, so the desktop footprint stays small.

## FAQ

**Does it upload my Codex conversations?** No. Local usage files are read locally and never sent to a project server.

**Does it replace the official Codex quota?** No. The official account response is the source of truth for quota; this app makes it easier to see.

**Are the API prices a bill?** No. They are a public-price equivalent calculated from observed Token categories and clearly marked as estimates.

**Why is there no browser pop-up every five minutes?** The reset poll is refreshed silently in the background. Clicking a forecast orb opens codex-reset.com only when you ask for it.

## Give it a star or report an edge case

If this saves you from a quota surprise, a Star helps other Codex users discover the project. If a parser or macOS presentation is wrong, please open an [Issue](https://github.com/KK-best/codex-quota-orb/issues) with your macOS version and a redacted description — never attach credentials or private conversation data.

## License

MIT. See [LICENSE](LICENSE).
