Build a very small, fast, native macOS menu-bar application called **wyd-barman**.

`wyd-barman` is a graphical macOS companion for the existing `wyd` project.

It must **NOT duplicate the logic already implemented in `wyd`**.

`wyd` remains the engine and source of truth.

`wyd-barman` is only a thin native macOS control surface for it.

The relationship is:

```text
wyd
├── process discovery
├── session detection
├── ownership resolution
├── project grouping
├── resource tracking
├── coding-agent detection
├── MCP detection
├── dev-server detection
├── port detection
├── Docker/resource detection
├── leftover detection
├── cleanup planning
└── safety rules

              ↓ machine-readable interface

wyd-barman
├── macOS menu bar UI
├── display current state
├── Start
├── Stop
├── Restart
├── Kill
├── Cleanup Review
├── confirmations
└── launch at login
```

The core rule of this project is:

> **Never reimplement in Swift what `wyd` already knows how to determine.**

If information is missing from `wyd`, extend `wyd` with a stable machine-readable interface instead of duplicating its logic inside `wyd-barman`.

---

# Product purpose

`wyd-barman` should let a developer click one icon in the macOS menu bar and instantly answer:

- What development projects are currently running?
- Which coding agents are active?
- What servers did they start?
- What ports are open?
- What Docker containers belong to them?
- Which databases/services are running?
- Which MCP servers are running?
- Which Chromium/Playwright processes are still alive?
- What resources were left behind by ended sessions?
- What can safely be stopped?
- What can safely be cleaned up?

The normal workflow should be:

```text
click menu bar
→ see current dev environment
→ Stop / Restart / Clean
```

No terminal should be required for normal use.

---

# Architecture principle

Do NOT build another process monitor.

Do NOT independently scan processes using `ps`, `lsof`, `libproc`, `sysctl`, Docker APIs, Homebrew APIs, or custom heuristics unless there is an extremely small piece of macOS-specific UI functionality that cannot reasonably belong in `wyd`.

`wyd-barman` should obtain its state from `wyd`.

For example:

```bash
wyd snapshot --json
```

and send actions back through `wyd`:

```bash
wyd action stop ...
wyd action restart ...
wyd action kill ...
wyd cleanup ...
```

If these interfaces do not exist yet, design and implement them in `wyd`.

---

# Primary goal

The app should feel like:

> **a tiny native macOS remote control for wyd**

not:

> another implementation of wyd written in Swift.

---

# Technology

Build `wyd-barman` with:

- Swift
- SwiftUI
- `MenuBarExtra`
- AppKit only when SwiftUI is insufficient
- async/await
- Codable for JSON
- native macOS APIs
- `SMAppService` for Launch at Login

Do not use:

- Electron
- Tauri
- Node
- embedded webviews
- local HTTP servers
- bundled browser runtimes
- database storage unless genuinely needed
- large third-party frameworks

The application should normally have **no Dock icon**.

It should live entirely in the menu bar.

---

# Performance goals

This app must be extremely small and unobtrusive.

Priorities:

1. Instant menu opening
2. Tiny memory footprint
3. Essentially zero idle CPU
4. Minimal energy usage
5. No unnecessary polling
6. No expensive duplicate discovery

The expensive intelligence belongs in `wyd`.

The GUI should mostly:

```text
invoke wyd
→ decode JSON
→ render
```

and:

```text
user clicks action
→ invoke wyd action
→ refresh state
```

---

# Required `wyd` interface

Before building substantial UI, establish a stable machine-readable API from `wyd`.

Prefer a single snapshot command:

```bash
wyd snapshot --json
```

It should expose everything needed by the UI in one consistent model.

Conceptually:

```json
{
  "schema_version": 1,
  "generated_at": "...",

  "projects": [],
  "sessions": [],
  "resources": [],
  "services": [],
  "containers": [],
  "leftovers": []
}
```

Avoid making the menu app execute ten different expensive commands every refresh.

The snapshot should represent a coherent point-in-time view.

---

# JSON API requirements

The machine-readable format must:

- be versioned
- use stable IDs
- be deterministic
- distinguish display labels from internal identifiers
- expose available actions
- expose ownership confidence where relevant
- expose cleanup/safety information
- avoid requiring the GUI to infer process relationships
- avoid requiring the GUI to parse commands or process names

For example:

```json
{
  "id": "resource_abc123",
  "kind": "dev_server",
  "name": "Vite",
  "status": "running",
  "project_id": "project_csv2cal",
  "session_id": "session_xyz",
  "port": 5173,
  "pid": 4812,
  "memory_bytes": 180000000,
  "cpu_percent": 1.2,
  "actions": [
    "stop",
    "kill",
    "open"
  ]
}
```

The GUI should not need logic like:

```text
if command contains "vite"
then classify as Vite
```

That belongs in `wyd`.

---

# Stable identifiers

Do not use PID alone as an identity.

Use durable IDs generated by `wyd`.

For example:

```text
project_csv2cal
session_01J...
resource_01J...
container_01J...
```

PIDs may be exposed as diagnostic metadata but should not be the primary UI/action identity.

This prevents PID reuse problems and keeps actions tied to the correct resource.

---

# Actions API

Create a simple machine-readable action interface.

Possible shape:

```bash
wyd action stop resource_01J...
wyd action restart resource_01J...
wyd action kill resource_01J...

wyd action stop session_01J...
wyd action stop project_01J...
```

Or:

```bash
wyd action \
  --target resource_01J... \
  --action stop \
  --json
```

The exact syntax is less important than:

- stable IDs
- structured output
- clear error handling
- safety validation inside `wyd`

The GUI must not implement kill logic itself.

For example, the GUI should NOT do:

```swift
kill(pid, SIGTERM)
```

when the target is a `wyd` resource.

Instead:

```text
wyd decides how this resource should be stopped.
```

That allows `wyd` to choose correctly between:

- SIGTERM
- SIGKILL
- Docker stop
- Docker Compose down
- service-manager action
- agent/session cleanup
- another appropriate mechanism

---

# Available actions

Every resource returned by `wyd` should expose its supported actions.

Example:

```json
{
  "actions": [
    "stop",
    "restart",
    "kill"
  ]
}
```

A stopped Homebrew service could return:

```json
{
  "actions": [
    "start"
  ]
}
```

A web server could return:

```json
{
  "actions": [
    "open",
    "stop",
    "restart"
  ]
}
```

The UI renders actions provided by the engine rather than maintaining a second capability matrix.

---

# Main menu

The menu bar popup should be compact and native.

Conceptually:

```text
wyd-barman
────────────────────────────

PROJECTS

● csv2cal
  OpenCode · 8 resources · 640 MB

  Vite                 :5173
  API                  :3001
  Chromium ×4
  chrome-devtools-mcp

                       Stop ▸


● cloudfacts
  Claude Code · 4 resources · 310 MB

  Astro                :4321
  playwright-mcp

                       Stop ▸


SERVICES

● PostgreSQL           :5432
● Redis                :6379


DOCKER

● postgres-dev         :5432
● redis                :6379


AGENTS

● Claude Code
  cloudfacts · working · 12m

● OpenCode
  csv2cal · idle · 37m


LEFTOVERS

⚠ 12 resources
  ~1.7 GB reclaimable

                       Review


────────────────────────────
Refresh
Settings
Quit
```

Do not copy this literally.

It defines information hierarchy.

---

# Project-centric UX

The primary UI should show **projects and sessions**, not a giant flat process list.

Example:

```text
csv2cal
  OpenCode

  Vite :5173
  API :3001
  Chromium ×4
  playwright-mcp
```

`wyd` determines the relationships.

`wyd-barman` only renders them.

---

# Sections

The default menu can contain sections such as:

```text
Projects
Agents
Services
Docker
Leftovers
```

But avoid duplication.

For example, if PostgreSQL belongs to a project's Docker stack, the UI may show it under the project and optionally summarize it under Docker.

Use IDs/relationships from `wyd` to avoid representing the same resource as unrelated entries.

---

# Development servers

`wyd` should identify servers such as:

- Vite
- Astro
- Next.js
- Nuxt
- Laravel
- Rails
- Django
- Flask
- FastAPI
- Node
- Bun
- Deno
- Storybook

`wyd-barman` should receive already-normalized data such as:

```json
{
  "kind": "dev_server",
  "name": "Vite",
  "port": 5173
}
```

The GUI should display:

```text
Vite :5173
```

not raw command lines.

Raw command/PID may appear in an advanced detail view.

---

# Open in browser

When `wyd` identifies a resource as an HTTP/web server, expose an `open` action or URL.

Example:

```json
{
  "url": "http://localhost:5173",
  "actions": ["open", "stop"]
}
```

The macOS app can use native APIs to open the URL.

This is one of the few actions that may reasonably be implemented directly in the UI after receiving the URL from `wyd`.

---

# Docker

Docker discovery and ownership should belong to `wyd`.

`wyd` may internally use Docker CLI/API and support:

- Docker Desktop
- OrbStack
- Colima
- Rancher Desktop
- standard Docker contexts

`wyd-barman` should not implement a separate Docker discovery layer.

It receives normalized objects such as:

```json
{
  "id": "container_...",
  "kind": "container",
  "name": "postgres-dev",
  "compose_project": "csv2cal",
  "ports": [5432],
  "status": "running",
  "actions": [
    "stop",
    "restart"
  ]
}
```

UI actions should call `wyd`.

---

# Databases and services

`wyd` should classify infrastructure such as:

- PostgreSQL
- MySQL
- MariaDB
- Redis
- Valkey
- MongoDB
- Elasticsearch
- OpenSearch
- RabbitMQ
- NATS
- MinIO
- ClickHouse

It should also know their origin where possible:

```text
Docker
Homebrew
standalone
```

Example normalized object:

```json
{
  "kind": "database",
  "name": "PostgreSQL",
  "origin": "docker",
  "port": 5432,
  "status": "running"
}
```

Again, Barman only renders this.

---

# Homebrew services

If Homebrew service support is useful, implement it inside `wyd`.

Do not run:

```bash
brew services list
```

from Swift independently if `wyd` already handles or can handle that domain.

The UI should receive:

```json
{
  "kind": "service",
  "manager": "homebrew",
  "name": "redis",
  "status": "running",
  "actions": [
    "stop",
    "restart"
  ]
}
```

---

# Coding agents

Agent/session ownership is one of `wyd`'s core strengths.

Do not duplicate it.

The snapshot should expose agent sessions such as:

- Claude Code
- Codex
- OpenCode
- Gemini CLI
- aider
- other detected coding agents

Example:

```json
{
  "id": "session_...",
  "kind": "agent_session",
  "agent": "OpenCode",
  "project_id": "project_csv2cal",
  "status": "idle",
  "age_seconds": 2200,
  "resource_ids": [
    "resource_vite",
    "resource_chromium",
    "resource_mcp"
  ]
}
```

Possible states:

```text
working
idle
waiting
ended
unknown
```

The macOS UI should not infer those states itself.

---

# MCP servers

`wyd` handles detection and ownership.

The UI may receive:

```json
{
  "kind": "mcp",
  "name": "chrome-devtools-mcp",
  "session_id": "...",
  "project_id": "..."
}
```

Display them as child resources of their owning session/project where possible.

---

# Chromium / Playwright

Do NOT scan Chromium processes independently inside `wyd-barman`.

`wyd` determines whether a browser process is:

- normal user Chrome
- Playwright Chromium
- Chrome for Testing
- browser spawned by an MCP server
- agent-owned browser
- potential leftover

The GUI trusts the classification and safety information returned by `wyd`.

This is critical.

Never let the GUI implement rules like:

```text
process name contains "Chromium" → killable
```

---

# Leftovers

`wyd` should remain the only authority for determining whether something is a leftover.

Snapshot example:

```json
{
  "id": "resource_...",
  "classification": "leftover",
  "confidence": "high",
  "reason": [
    "Owning OpenCode session ended",
    "Resource is still running",
    "No active session references this resource"
  ],
  "estimated_reclaim_bytes": 380000000
}
```

The UI should display the explanation where useful.

---

# Cleanup planning

Do not make Barman independently choose resources to kill.

Use a cleanup-plan API in `wyd`.

For example:

```bash
wyd cleanup plan --json
```

Response:

```json
{
  "plan_id": "cleanup_01J...",
  "items": [
    {
      "resource_id": "resource_...",
      "selected": true,
      "safe": true,
      "reason": "Owning session ended 47 minutes ago"
    }
  ],
  "protected": [
    {
      "resource_id": "resource_postgres",
      "reason": "Persistent database service"
    }
  ],
  "estimated_reclaim_bytes": 1700000000
}
```

Then:

```bash
wyd cleanup execute cleanup_01J... --json
```

The safety decision remains inside `wyd`.

---

# Cleanup UI

The GUI renders the plan.

Example:

```text
Cleanup Review

OpenCode · csv2cal
session ended 47m ago

✓ Chromium ×6        1.1 GB
✓ playwright-mcp     120 MB
✓ Vite :5173         190 MB

Protected:

  PostgreSQL
  Redis

Estimated reclaim:
1.4 GB

Cancel               Clean
```

The user can optionally deselect items if the `wyd` cleanup-plan format supports it.

Any modified plan must still be validated by `wyd` before execution.

---

# Graceful stop versus force kill

The UI should distinguish:

```text
Stop
```

from:

```text
Force Kill
```

But the implementation remains in `wyd`.

`wyd` decides what "Stop" means for each resource type.

Possible implementation:

```text
normal process → SIGTERM
Docker container → docker stop
Compose stack → compose stop/down
Homebrew service → service stop
agent session → session-aware shutdown
```

The GUI does not need to know these details.

---

# Start and restart

The user wants Barman to control services, not just kill them.

Therefore `wyd` should expose start/restart actions where it knows how.

Examples:

```text
PostgreSQL       Start
Redis            Restart
Docker stack     Start
Vite             Restart
```

The GUI only renders an action if `wyd` reports that it is available.

---

# Known project commands

If project start commands are needed, put their configuration into the `wyd` ecosystem rather than inventing a separate Barman config format unless there is a strong reason.

Possible project metadata:

```toml
[project]
name = "csv2cal"

[[service]]
name = "Web"
command = ["pnpm", "dev"]

[[service]]
name = "API"
command = ["pnpm", "api"]

[[service]]
name = "Stack"
command = ["docker", "compose", "up", "-d"]
```

`wyd` reads this.

`wyd-barman` sees only normalized actions such as:

```json
{
  "name": "Web",
  "status": "stopped",
  "actions": ["start"]
}
```

Avoid having both applications parse project configuration independently.

---

# WydClient

The central piece of Barman should be a very small Swift abstraction:

```text
WydClient
```

Responsibilities:

```text
locate wyd
run wyd snapshot --json
decode Snapshot
run actions
decode ActionResult
handle errors/timeouts
```

Conceptually:

```swift
protocol WydClient {
    func snapshot() async throws -> Snapshot

    func perform(
        action: ResourceAction,
        targetID: String
    ) async throws -> ActionResult

    func cleanupPlan() async throws -> CleanupPlan

    func executeCleanup(
        planID: String
    ) async throws -> CleanupResult
}
```

Keep it boring and small.

---

# Executing wyd

Use `Process` or an appropriate native API to invoke the binary.

Do not invoke it through arbitrary shell interpolation.

Prefer:

```text
executable:
  /opt/homebrew/bin/wyd

arguments:
  ["snapshot", "--json"]
```

Requirements:

- asynchronous
- cancellation
- timeout
- stdout capture
- stderr capture
- exit status
- structured errors
- no UI thread blocking

---

# Locating wyd

The GUI should automatically find `wyd`.

Check reasonable locations such as:

```text
/opt/homebrew/bin/wyd
/usr/local/bin/wyd
~/.local/bin/wyd
PATH
```

Because GUI apps may not inherit the interactive shell environment correctly, handle PATH discovery explicitly.

Allow the user to select a custom binary in Settings.

---

# Missing wyd

If `wyd` is not installed, do not crash.

Show a minimal state:

```text
wyd not found

wyd-barman requires the wyd engine.

[Install wyd]
[Locate…]
```

If there is a safe supported installation mechanism, offer it.

Otherwise link to installation instructions.

Do not silently install software.

---

# Version compatibility

Because `wyd-barman` depends on a machine-readable `wyd` interface, implement explicit version negotiation.

For example:

```bash
wyd api-version --json
```

or include it in the snapshot:

```json
{
  "schema_version": 1,
  "wyd_version": "0.8.0"
}
```

Barman should detect unsupported schema versions and show a useful message.

Example:

```text
wyd needs to be updated.
```

Do not fail with a JSON decoding error.

---

# Error handling

Errors should be short and actionable.

Examples:

```text
Could not stop Vite.
```

with expandable detail:

```text
wyd returned exit code 1:
process already exited
```

or:

```text
Docker runtime unavailable.
```

Avoid intrusive modal dialogs for minor refresh failures.

---

# Refresh strategy

Because `wyd` does the discovery, Barman should not aggressively poll.

Suggested approach:

### Menu open

```text
refresh every 2–5 seconds
```

### Menu closed

Prefer:

```text
10–30 seconds
```

or even less frequently if `wyd` supports change notifications later.

Avoid concurrent refreshes.

If a refresh is still running, do not start another.

After user actions:

```text
perform action
→ immediately refresh
```

---

# Future optimization

If spawning `wyd snapshot --json` periodically proves inefficient, preserve the architecture but optionally add a long-lived machine interface later.

For example:

```text
wyd serve --socket ~/.wyd/wyd.sock
```

with:

```text
Unix domain socket
```

or a lightweight local IPC mechanism.

Do NOT start with this unless measurement proves CLI invocation is a real problem.

The MVP should use the simplest reliable interface.

---

# UI performance

Menu opening must not wait for a fresh `wyd` call.

Maintain the latest snapshot in memory.

Flow:

```text
background refresh
→ update cached snapshot

user opens menu
→ render cached state immediately
→ refresh asynchronously
→ update rows if changed
```

Never show a spinner for the whole menu just because `wyd` is refreshing.

---

# UI structure

Suggested source layout:

```text
wyd-barman/
├── App/
│   └── WydBarmanApp.swift
│
├── MenuBar/
│   ├── MenuBarView.swift
│   ├── ProjectSection.swift
│   ├── AgentSection.swift
│   ├── ServiceSection.swift
│   ├── DockerSection.swift
│   └── LeftoversSection.swift
│
├── Wyd/
│   ├── WydClient.swift
│   ├── WydLocator.swift
│   ├── WydModels.swift
│   └── WydError.swift
│
├── State/
│   └── AppState.swift
│
├── Cleanup/
│   └── CleanupView.swift
│
└── Settings/
    └── SettingsView.swift
```

Keep the project very small.

---

# Native macOS design

The UI should feel like a system utility.

Use:

- system fonts
- SF Symbols
- native separators
- native context menus
- standard spacing
- standard buttons
- native materials
- native menu behavior

Avoid:

- SaaS dashboard cards
- giant headers
- gradients
- marketing visuals
- excessive rounded rectangles
- custom navigation
- web-like sidebars
- animations that slow interaction

Mental references:

- macOS Wi-Fi menu
- Bluetooth menu
- Battery menu
- iStat Menus
- Little Snitch-style utilities

---

# Default row design

A resource row should be very compact.

Example:

```text
● Vite                         :5173
```

or:

```text
● PostgreSQL                   :5432
```

Secondary metadata can be subtle.

Hover/context menu:

```text
Open
Stop
Restart
──────────
Details
Force Kill
```

Do not clutter every row with four permanent buttons.

---

# Projects

Project rows should summarize the resources already resolved by `wyd`.

Example:

```text
csv2cal
OpenCode · 8 resources · 640 MB

Vite                      :5173
API                       :3001
Chromium ×4
chrome-devtools-mcp
```

Possible project action:

```text
Stop
```

which calls the appropriate project/session action in `wyd`.

Do not iterate over child PIDs in the GUI.

---

# Resource usage

If `wyd` provides CPU/RAM totals, display them.

Example:

```text
8 resources · 640 MB
```

The GUI should not independently calculate CPU/memory aggregates unless the data genuinely cannot be supplied by `wyd`.

Prefer one source of truth.

---

# Menu bar icon

Use a tiny monochrome native menu-bar icon.

The branding can subtly reference:

- bartender
- bar
- process control
- wyd

But keep it professional.

Potential status variations:

```text
normal
cleanup available
warning
```

No animation.

No constantly changing CPU number in the menu bar.

---

# Product personality

Name:

# wyd-barman

Relationship:

```text
wyd = engine
wyd-barman = macOS remote control
```

Possible description:

> Native macOS menu-bar control for wyd.

Possible tagline:

> Keep your dev bar clean.

Or:

> See it. Stop it. Clean it.

Keep playful language subtle.

The product itself must feel trustworthy because it can terminate processes.

---

# Settings

Keep Settings minimal.

Possible settings:

```text
General

Launch at Login            ✓
Refresh frequency          Auto

wyd

Binary
/opt/homebrew/bin/wyd

Version
0.8.0

Behavior

Confirm project stop       ✓
Confirm cleanup            ✓
```

Do not create settings for discovery rules that belong to `wyd`.

For example, ignored processes, ownership rules, cleanup safety, etc. should ideally be configured in `wyd`, not separately in Barman.

---

# Launch at Login

Use:

```text
SMAppService
```

Do not modify shell startup files.

---

# Safety boundary

This is extremely important.

`wyd-barman` must not independently decide that something is safe to terminate.

It should display safety decisions returned by `wyd`.

For destructive actions:

```text
UI requests action
→ wyd validates target
→ wyd performs action
→ structured result returned
```

Do not expose APIs that allow stale GUI state to blindly kill a recycled PID.

Use stable IDs and revalidation inside `wyd`.

---

# Action validation

Suppose the UI snapshot says:

```text
resource X = Vite PID 123
```

but before the user clicks Stop, PID 123 exits and the PID gets reused.

The action must NOT kill the new process.

Therefore:

```text
wyd action stop resource_X
```

must re-resolve the resource and validate identity.

This safety belongs in `wyd`.

---

# MVP

Build the first version around:

1. Native macOS `MenuBarExtra`
2. No Dock icon
3. Locate installed `wyd`
4. Version compatibility check
5. `wyd snapshot --json`
6. Cached snapshot state
7. Project section
8. Agents section
9. Dev servers / ports
10. Services/databases section
11. Docker resources section
12. Leftovers section
13. Stop action
14. Restart action
15. Force Kill action
16. Project/session Stop
17. Cleanup Plan
18. Cleanup Review
19. Cleanup Execute
20. Launch at Login
21. Minimal Settings
22. Graceful handling when `wyd` is unavailable

---

# Work required in wyd

Treat missing engine capabilities as explicit `wyd` work.

Likely additions:

```text
wyd snapshot --json

wyd action <action> <stable-id> --json

wyd cleanup plan --json

wyd cleanup execute <plan-id> --json
```

Potentially:

```text
wyd api-version --json
```

Before modifying `wyd`, inspect its existing command structure and reuse current abstractions.

Do not create parallel resource/session representations solely for Barman.

Expose the existing internal model cleanly.

---

# Shared contract

If practical, define a documented JSON schema under `wyd`.

For example:

```text
docs/barman-api.md
```

or:

```text
schemas/snapshot-v1.json
```

The contract should belong to `wyd`, because `wyd` owns the data model.

`wyd-barman` consumes it.

This also leaves open the possibility of future clients without coupling `wyd` specifically to Swift.

---

# Non-goals

Do NOT turn `wyd-barman` into:

- another process discovery engine
- Docker Desktop replacement
- Activity Monitor replacement
- database GUI
- terminal
- SSH manager
- Kubernetes UI
- generic process killer
- independent coding-agent monitor

If implementing a feature requires duplicating a large piece of `wyd`, stop and expose that capability from `wyd` instead.

---

# Quality bar

Before considering the MVP complete, verify:

- menu appears immediately
- no Dock icon
- UI never blocks on `wyd`
- latest snapshot is cached
- refreshes cannot overlap
- malformed JSON does not crash the app
- incompatible `wyd` versions produce a useful message
- missing `wyd` produces a useful message
- stale resource IDs cannot kill unrelated processes
- Stop routes through `wyd`
- Kill routes through `wyd`
- Docker actions route through `wyd`
- cleanup safety remains in `wyd`
- normal browsers are never killed due to GUI-side heuristics
- app has effectively zero idle CPU
- memory usage stays very small
- menu remains responsive even if `wyd` hangs
- every external invocation has a timeout

---

# Performance measurement

Measure:

```text
cold app startup
menu-open latency
idle memory
idle CPU
snapshot execution time
snapshot JSON size
refresh CPU cost
```

If performance is poor, optimize based on measurement.

Do not prematurely add a daemon or socket protocol.

The target architecture should remain:

```text
                ┌───────────────┐
                │      wyd      │
                │               │
                │ discovery     │
                │ ownership     │
                │ sessions      │
                │ Docker        │
                │ agents        │
                │ leftovers     │
                │ cleanup       │
                └───────┬───────┘
                        │
                 JSON / actions
                        │
                ┌───────▼───────┐
                │  wyd-barman   │
                │               │
                │ native macOS  │
                │ menu-bar UI   │
                └───────────────┘
```

---

# Implementation approach

Start by inspecting the current `wyd` repository.

Do not assume commands or internal APIs that do not exist.

First identify:

- current process/session models
- current resolver
- current cleanup logic
- existing CLI command structure
- existing serialization support
- existing Docker/service support
- stable identifiers already available

Then propose the **smallest set of changes to `wyd`** required to support Barman.

Do not refactor unrelated parts of `wyd`.

After the machine-readable interface works, implement the Swift app.

---

# Deliverables

Produce:

1. short analysis of current `wyd` architecture
2. proposed minimal additions to `wyd`
3. Snapshot v1 JSON contract
4. action API contract
5. cleanup-plan API contract
6. Swift data models
7. `WydClient`
8. menu information architecture
9. native macOS MVP
10. performance measurements
11. README with installation instructions

The final result should be:

> **wyd-barman — a tiny native macOS menu-bar remote control powered by wyd.**

The intelligence belongs in `wyd`.

The convenience belongs in `wyd-barman`.