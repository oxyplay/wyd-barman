![wyd-barman](logo.svg)

# wyd-barman

Tiny native macOS menu-bar remote control for [wyd](https://wyd.sh) (the engine).
No Dock icon. Renders a cached `wyd barman snapshot`, routes every control
action through `wyd`, never scans processes itself.

> Intelligence belongs in `wyd`. Convenience belongs in `wyd-barman`.

## Requirements

- macOS 14+, Xcode 16.4 / Swift 6
- `wyd` 0.9.0+ with the `barman` subcommand (`wyd barman version --json`
  must report `schema_version == 1`)

## Install

```bash
git clone <this-repo> && cd wyd-barman
xcodebuild -project wyd-barman.xcodeproj -scheme wyd-barman -configuration Release build
open ~/Library/Developer/Xcode/DerivedData/wyd-barman-*/Build/Products/Release/wyd-barman.app
```

The app locates `wyd` via, in order:

1. Settings override (`wydBinaryPath`, file picker)
2. `/opt/homebrew/bin/wyd`, `/usr/local/bin/wyd`, `~/.local/bin/wyd`
3. Login-shell `PATH` (`zsh -l -c 'command -v wyd'`)

Missing → "wyd not found" state with install link, never a crash.
Incompatible schema → "wyd needs to be updated", never a decode crash.

## Use

Click the menu-bar glass → cached snapshot renders instantly, then
refreshes (on open + every 10s while open; a light background poll every
3 min while closed).

Sections:

- **STATUS** — one line: `CPU · RAM · Disk free` (measured by the engine).
- **FRONTENDS** — everything running with a URL; one click opens the
  browser (URL supplied by the engine only).
- **PROJECTS** — per project: resources, total RAM, Stop (with confirm).
- **SERVICES / DOCKER** — databases and containers; Docker rolls up into a
  submenu (running first, then stopped) with a disk-usage line.
- **AGENTS** — active coding-agent sessions; ended ones are summarized.
- **LEFTOVERS → Review** — cleanup plan backed by
  `wyd barman cleanup-plan` / `execute` (deselect supported, still
  engine-validated).

Every row's submenu is built verbatim from the engine's `actions` array
(Open / Start / Stop / Restart); Force Kill is a two-step submenu.
Footer: Keep awake (no sleep / no screen saver via `IOPMAssertion`),
Settings, Quit.

Settings: Launch at Login (`SMAppService`), Keep awake, Demo mode (the
engine's deterministic synthetic dataset — safe to click around for
screenshots), binary path + detected version, confirm toggles for project
stop and cleanup.

## Architecture

```
wyd                          wyd-barman
discovery/ownership/safety   menu-bar UI only
  │ JSON: barman snapshot/action/cleanup-plan/execute/version
  ▼
WydClient (Process, argv only, 8s snapshot / 30s action timeouts)
  → AppState (cached snapshot, inFlight guard, banner errors)
  → MenuBarView / CleanupView / SettingsView
```

No `ps`/`lsof`/`libproc`/`kill(` outside the `Process` timeout-terminate;
no command-name heuristics anywhere in Swift. Verify:

```bash
grep -rn "kill(\|lsof\|libproc\|brew services" App MenuBar State
```

## Performance (measured 2026-09-11, M1 Pro)

| Metric | Value |
|---|---|
| `wyd barman snapshot --json` wall (live host, 30 resources + 9 containers) | 0.26 s |
| `wyd barman snapshot --json --demo` wall | < 0.02 s |
| Snapshot JSON size (live / demo) | ~32 KB / ~16 KB |
| App bundle (Debug) | 1.3 MB |
| Menu-open latency | instant on cache (renders `snapshot` synchronously, refreshes async every 3 s while open) |
| Idle CPU / memory <60 MB | spot-check in Instruments before release (not measured in this headless build) |

Refresh policy: menu-open 3 s, menu-closed Auto 20 s / Frequent 5 s /
Paused; `inFlight` drops overlaps; every action triggers an immediate
re-refresh. No daemon/socket fast path until measurement proves the CLI
is a problem (p95 target < 2 s; currently 0.26 s).
