import AppKit
import SwiftUI

func formatBytes(_ bytes: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .memory
    return formatter.string(fromByteCount: Int64(bytes))
}

func formatAge(_ seconds: UInt64) -> String {
    if seconds < 60 { return "\(seconds)s" }
    if seconds < 3_600 { return "\(seconds / 60)m" }
    if seconds < 86_400 { return "\(seconds / 3_600)h" }
    return "\(seconds / 86_400)d"
}

/// Native AppKit menu (`.menuBarExtraStyle(.menu)`): the system renders and
/// opens it instantly, no window juggling. Sections render via `Section`
/// headers; every resource row is a submenu of action items built verbatim
/// from the engine's `actions` array. Force Kill is a two-step submenu —
/// native menus close before any dialog, so no `confirmationDialog` here.
struct MenuBarView: View {
    @Bindable var state: AppState

    var body: some View {
        Group {
            if state.snapshot == nil {
                Group {
                    if state.errorBanner == "wyd not found" {
                        missingWyd
                    } else if state.errorBanner == "wyd needs to be updated" {
                        incompatibleWyd
                    } else {
                        ProgressView("Loading…")
                    }
                }
            } else {
                menuItems
            }
            Divider()
            footer
        }
        .task {
            // Open-menu refresh: render cache instantly, then refresh every
            // 10s until the menu closes (native menu content only lives
            // while open). No background refresh when closed.
            await state.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await state.refresh()
            }
        }
    }

    private var menuItems: some View {
        Group {
            if let snapshot = state.snapshot {
                // One-line status, no section header.
                Text(snapshot.system.oneLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let banner = state.errorBanner {
                Section {
                    Text(banner).foregroundStyle(.red)
                    if let detail = state.errorDetail {
                        Text(detail).foregroundStyle(.secondary)
                    }
                }
            }
            if let snapshot = state.snapshot {
                if !snapshot.projects.isEmpty {
                    Section("PROJECTS") {
                        ForEach(snapshot.projects) { project in
                            ProjectRow(state: state, project: project)
                        }
                    }
                }
                let services = snapshot.resources.filter {
                    ["database", "dev_service", "service"].contains($0.kind)
                }
                if !services.isEmpty {
                    Section("SERVICES") {
                        ForEach(services) { resource in
                            ResourceRow(state: state, resource: resource)
                        }
                    }
                }
                if !snapshot.containers.isEmpty {
                    Section("DOCKER") {
                        ForEach(snapshot.containers) { container in
                            ContainerRow(state: state, container: container)
                        }
                    }
                }
                let active = snapshot.sessions.filter { $0.status != "ended" }
                if !active.isEmpty {
                    Section("AGENTS") {
                        ForEach(active.prefix(10)) { session in
                            SessionRow(state: state, session: session)
                        }
                        let ended = snapshot.sessions.filter { $0.status == "ended" }.count
                        if ended > 0 {
                            Text("+ \(ended) ended").foregroundStyle(.secondary)
                        }
                    }
                }
                if snapshot.leftovers.count > 0 {
                    Section("LEFTOVERS") {
                        Button("Review \(snapshot.leftovers.count) · \(formatBytes(snapshot.leftovers.estimatedReclaimBytes))") {
                            Task { await state.fetchCleanupPlan() }
                            openCleanup()
                        }
                    }
                }
            }
        }
    }

    @Environment(\.openWindow) private var openWindow
    private func openCleanup() {
        openWindow(id: "cleanup")
    }

    // MARK: - Engine states

    private var missingWyd: some View {
        Group {
            Text("wyd not found")
            Text("wyd-barman requires the wyd engine.").foregroundStyle(.secondary)
            Link("Install wyd", destination: WydLocator.installURL)
            Button("Locate…") { locateBinary() }
        }
    }

    private var incompatibleWyd: some View {
        Group {
            Text("wyd needs to be updated")
            if let detail = state.errorDetail {
                Text(detail).foregroundStyle(.secondary)
            }
            Button("Check again") { Task { await state.refresh() } }
        }
    }

    private func locateBinary() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: WydLocator.overrideKey)
            Task { await state.refresh() }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Group {
            Toggle("Keep awake", isOn: $state.preventSleep)
            SettingsLink()
            Button("Quit wyd-barman") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

// MARK: - Rows

/// `● Name :port` item with a submenu of actions from the engine.
struct ResourceRow: View {
    @Bindable var state: AppState
    let resource: Resource

    var body: some View {
        Menu {
            ForEach(resource.actions, id: \.self) { token in
                if token == "open", let urlString = resource.url, let url = URL(string: urlString) {
                    Button("Open") { NSWorkspace.shared.open(url) }
                } else if let action = ResourceAction(rawValue: token), action != .open,
                    action != .kill
                {
                    Button(ActionIcon.name(token)) {
                        Task {
                            await state.perform(
                                target: resource.id, action: action, displayName: resource.name)
                        }
                    }
                }
            }
            if resource.actions.contains("kill") {
                Divider()
                Menu("Force Kill") {
                    Button("Kill \(resource.name)", role: .destructive) {
                        Task {
                            await state.perform(
                                target: resource.id, action: .kill, displayName: resource.name)
                        }
                    }
                }
            }
            if let pid = resource.pid {
                Divider()
                Text("PID \(pid) · \(formatBytes(resource.memoryBytes))").foregroundStyle(.secondary)
            }
        } label: {
            rowLabel
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 6) {
            Text("●").font(.caption2)
            Text(resource.name).lineLimit(1).truncationMode(.middle)
            Spacer()
            if let port = resource.port {
                Text(":\(port)").foregroundStyle(.secondary).font(.callout)
            }
        }
        .frame(width: 260, alignment: .leading)
    }
}

struct ProjectRow: View {
    @Bindable var state: AppState
    let project: Project

    var body: some View {
        Menu {
            ForEach(state.members(of: project)) { resource in
                ResourceRow(state: state, resource: resource)
            }
            Divider()
            Button("Stop \(project.name)", role: .destructive) {
                Task {
                    await state.perform(target: project.id, action: .stop, displayName: project.name)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("●").font(.caption2)
                Text(project.name).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(formatBytes(project.memoryBytes)).foregroundStyle(.secondary).font(.caption)
            }
            .frame(width: 260, alignment: .leading)
        }
    }
}

struct ContainerRow: View {
    @Bindable var state: AppState
    let container: Container

    var body: some View {
        Menu {
            ForEach(container.actions, id: \.self) { token in
                if let action = ResourceAction(rawValue: token) {
                    Button(ActionIcon.name(token)) {
                        Task {
                            await state.perform(
                                target: container.id, action: action, displayName: container.name)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("●").font(.caption2)
                Text(container.name).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(container.status).foregroundStyle(.secondary).font(.callout)
            }
            .frame(width: 260, alignment: .leading)
        }
    }
}

struct SessionRow: View {
    @Bindable var state: AppState
    let session: Session

    var body: some View {
        Button {
            // Display-only row; deep session details live in wyd.
        } label: {
            HStack(spacing: 6) {
                Text(session.agent).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("\(state.name(forProjectID: session.projectID) ?? "—") · \(formatAge(session.ageSeconds))")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .frame(width: 260, alignment: .leading)
        }
        .disabled(true)
    }
}

/// Menu label words for engine action tokens.
enum ActionIcon {
    static func name(_ token: String) -> String {
        switch token {
        case "open": "Open"
        case "start": "Start"
        case "stop": "Stop"
        case "restart": "Restart"
        default: "Action"
        }
    }
}