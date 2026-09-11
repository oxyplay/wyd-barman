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

/// Native AppKit menu (`.menuBarExtraStyle(.menu)`). Native menu items
/// flatten SwiftUI labels to a single line of text — every row label here is
/// ONE composed `Text` ("● name :port"), never an HStack. Actions live in
/// submenus, built verbatim from the engine's `actions` array. Force Kill is
/// a two-step submenu (menus close before any dialog can appear).
struct MenuBarView: View {
    @Bindable var state: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if state.snapshot == nil {
                engineStateRows
            } else {
                menuItems
            }
            Divider()
            Toggle("Keep awake", isOn: $state.preventSleep)
            Button("Settings…") { openSettings() }
            Button("Quit wyd-barman") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .task {
            // Open-menu refresh: render cache instantly, then refresh every
            // 10s while open. No refresh when closed.
            await state.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await state.refresh()
            }
        }
    }

    // MARK: - Content

    private var menuItems: some View {
        Group {
            if let snapshot = state.snapshot {
                Text(snapshot.system.oneLine)
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
                        Button(
                            "Review \(snapshot.leftovers.count) · \(formatBytes(snapshot.leftovers.estimatedReclaimBytes))"
                        ) {
                            Task { await state.fetchCleanupPlan() }
                            openWindow(id: "cleanup")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Engine states

    @ViewBuilder
    private var engineStateRows: some View {
        if state.errorBanner == "wyd not found" {
            Text("wyd not found")
            Text("wyd-barman requires the wyd engine.").foregroundStyle(.secondary)
            Link("Install wyd", destination: WydLocator.installURL)
            Button("Locate…") { locateBinary() }
        } else if state.errorBanner == "wyd needs to be updated" {
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
}

func resourceLabel(_ resource: Resource) -> String {
    var label = "● \(resource.name)"
    if let port = resource.port {
        label += "  :\(port)"
    }
    return label
}

// MARK: - Rows

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
                    Button(actionName(token)) {
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
            Text(resourceLabel(resource))
        }
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
                    await state.perform(
                        target: project.id, action: .stop, displayName: project.name)
                }
            }
        } label: {
            Text("● \(project.name)  \(formatBytes(project.memoryBytes))")
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
                    Button(actionName(token)) {
                        Task {
                            await state.perform(
                                target: container.id, action: action, displayName: container.name)
                        }
                    }
                }
            }
        } label: {
            Text("● \(container.name)  (\(container.status))")
        }
    }
}

struct SessionRow: View {
    @Bindable var state: AppState
    let session: Session

    var body: some View {
        Button {} label: {
            Text(
                "\(session.agent) · \(state.name(forProjectID: session.projectID) ?? "—") · \(formatAge(session.ageSeconds))"
            )
        }
        .disabled(true)
    }
}

func actionName(_ token: String) -> String {
    switch token {
    case "open": "Open"
    case "start": "Start"
    case "stop": "Stop"
    case "restart": "Restart"
    default: "Action"
    }
}