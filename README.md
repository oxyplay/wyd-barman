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

Click the menu-bar glass → Projects / Services / Docker / Agents /
Leftovers sections render from cache instantly, then refresh. Every row's
menu is built verbatim from the engine's `actions` array (Open / Stop /
Restart / Force Kill). Leftovers → Review opens the Cleanup sheet backed
by `wyd barman cleanup-plan` / `execute` (deselect supported, still
engine-validated). Footer: Refresh / Settings / Quit.

Settings: Launch at Login (`SMAppService`), refresh cadence
(Auto 20s / Frequent 5s / Paused), binary path + detected version,
confirm toggles for project stop and cleanup.

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
