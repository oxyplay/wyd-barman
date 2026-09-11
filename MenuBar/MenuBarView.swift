import AppKit
import SwiftUI

func formatBytes(_ bytes: UInt64) -> String {
    // Fresh instance per call: ByteCountFormatter is not Sendable, and menu
    // rows are few enough that sharing buys nothing.
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

struct MenuBarView: View {
    @Bindable var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var locateError: String?

    var body: some View {
        Group {
            if state.snapshot == nil, state.errorBanner == "wyd not found" {
                missingWyd
            } else if state.snapshot == nil, state.errorBanner == "wyd needs to be updated" {
                incompatibleWyd
            } else {
                menuContent
            }
            Divider()
            footer
        }
        .task {
            // Menu-open refresh: render cache instantly (already done above),
            // then refresh every 3s until the menu closes.
            await state.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await state.refresh()
            }
        }
    }

    // MARK: - Sections

    private var menuContent: some View {
        Group {
            if let banner = state.errorBanner {
                Section {
                    Text(banner)
                    if let detail = state.errorDetail {
                        Text(detail)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let snapshot = state.snapshot {
                if !snapshot.projects.isEmpty {
                    Section("Projects") {
                        ForEach(snapshot.projects) { project in
                            ProjectRow(state: state, project: project)
                        }
                    }
                }
                let services = snapshot.resources.filter {
                    ["database", "dev_service", "service"].contains($0.kind)
                }
                if !services.isEmpty {
                    Section("Services") {
                        ForEach(services) { resource in
                            ResourceRow(state: state, resource: resource)
                        }
                    }
                }
                if !snapshot.containers.isEmpty {
                    Section("Docker") {
                        ForEach(snapshot.containers) { container in
                            ContainerRow(state: state, container: container)
                        }
                    }
                }
                if !snapshot.sessions.isEmpty {
                    Section("Agents") {
                        ForEach(snapshot.sessions) { session in
                            SessionRow(state: state, session: session)
                        }
                    }
                }
                Section("Leftovers") {
                    leftovers(snapshot: snapshot)
                }
            } else if state.inFlight {
                Text("Loading…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func leftovers(snapshot: Snapshot) -> some View {
        Group {
            if snapshot.leftovers.count == 0 {
                Text("Nothing left behind")
                    .foregroundStyle(.secondary)
            } else {
                Text(
                    "\(snapshot.leftovers.count) resources · \(formatBytes(snapshot.leftovers.estimatedReclaimBytes)) reclaimable"
                )
                Button("Review…") {
                    Task { await state.fetchCleanupPlan() }
                    openWindow(id: "cleanup")
                }
            }
        }
    }

    // MARK: - Engine states

    private var missingWyd: some View {
        Group {
            Text("wyd not found")
            Text("wyd-barman requires the wyd engine.")
                .foregroundStyle(.secondary)
            Link("Install wyd", destination: WydLocator.installURL)
            Button("Locate…") { locateBinary() }
            if let locateError {
                Text(locateError)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var incompatibleWyd: some View {
        Group {
            Text("wyd needs to be updated")
            if let detail = state.errorDetail {
                Text(detail)
                    .foregroundStyle(.secondary)
            }
            Button("Check again") {
                Task { await state.refresh() }
            }
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
            locateError = nil
            Task { await state.refresh() }
        } else {
            locateError = "No binary selected."
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Group {
            Button("Refresh") {
                Task { await state.refresh() }
            }
            .keyboardShortcut("r")
            SettingsLink()
            Button("Quit wyd-barman") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

// MARK: - Rows

/// One-line `● Name :port` row with subtle memory metadata; actions live in
/// the submenu, built verbatim from the engine's `actions` array.
struct ResourceRow: View {
    @Bindable var state: AppState
    let resource: Resource
    @State private var confirmingKill = false

    var body: some View {
        Menu {
            actionButtons
            Divider()
            details
        } label: {
            rowLabel
        }
    }

    private var rowLabel: some View {
        HStack {
            Text("● \(resource.name)")
            Spacer()
            if let port = resource.port {
                Text(":\(port)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionButtons: some View {
        Group {
            ForEach(resource.actions, id: \.self) { token in
                if token == "open", let urlString = resource.url, let url = URL(string: urlString) {
                    Button("Open") {
                        NSWorkspace.shared.open(url)
                    }
                } else if let action = ResourceAction(rawValue: token), action != .open,
                    action != .kill
                {
                    Button(actionLabel(action)) {
                        Task {
                            await state.perform(
                                target: resource.id, action: action,
                                displayName: resource.name)
                        }
                    }
                }
            }
            if resource.actions.contains("kill") {
                Divider()
                Button("Force Kill…") { confirmingKill = true }
                    .confirmationDialog(
                        "Force kill \(resource.name)?",
                        isPresented: $confirmingKill,
                        titleVisibility: .visible
                    ) {
                        Button("Force Kill", role: .destructive) {
                            Task {
                                await state.perform(
                                    target: resource.id, action: .kill,
                                    displayName: resource.name)
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    }
            }
        }
    }

    private func actionLabel(_ action: ResourceAction) -> String {
        switch action {
        case .open: "Open"
        case .start: "Start"
        case .stop: "Stop"
        case .restart: "Restart"
        case .kill: "Kill"
        }
    }

    private var details: some View {
        Text(detailsText)
            .foregroundStyle(.secondary)
    }

    private var detailsText: String {
        var parts: [String] = []
        if let pid = resource.pid { parts.append("PID \(pid)") }
        parts.append(formatBytes(resource.memoryBytes))
        if resource.cpuPercent > 0 {
            parts.append(String(format: "%.1f%% CPU", resource.cpuPercent))
        }
        if !resource.reasons.isEmpty {
            parts.append(resource.reasons.joined(separator: "; "))
        }
        return parts.joined(separator: " · ")
    }
}

struct ProjectRow: View {
    @Bindable var state: AppState
    let project: Project
    @State private var confirmingStop = false

    private var confirmStop: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.confirmProjectStop) as? Bool ?? true
    }

    var body: some View {
        Menu {
            ForEach(state.members(of: project)) { resource in
                ResourceRow(state: state, resource: resource)
            }
            Divider()
            Button("Stop…") { stopTapped() }
                .confirmationDialog(
                    "Stop \(project.name)?",
                    isPresented: $confirmingStop,
                    titleVisibility: .visible
                ) {
                    Button("Stop", role: .destructive) { stop() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(
                        "\(project.resourceCount) resources · \(formatBytes(project.memoryBytes))"
                    )
                }
        } label: {
            VStack(alignment: .leading) {
                Text("● \(project.name)")
                Text(
                    "\(project.agent ?? "unknown agent") · \(project.resourceCount) resources · \(formatBytes(project.memoryBytes))"
                )
                .foregroundStyle(.secondary)
            }
        }
    }

    private func stopTapped() {
        if confirmStop {
            confirmingStop = true
        } else {
            stop()
        }
    }

    private func stop() {
        Task {
            await state.perform(target: project.id, action: .stop, displayName: project.name)
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
                    Button(actionButtonLabel(action)) {
                        Task {
                            await state.perform(
                                target: container.id, action: action,
                                displayName: container.name)
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text("● \(container.name)")
                Spacer()
                Text(container.status)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func actionButtonLabel(_ action: ResourceAction) -> String {
        switch action {
        case .open: "Open"
        case .start: "Start"
        case .stop: "Stop"
        case .restart: "Restart"
        case .kill: "Force Kill"
        }
    }
}

struct SessionRow: View {
    @Bindable var state: AppState
    let session: Session

    var body: some View {
        HStack {
            Text("● \(session.agent)")
            Spacer()
            Text(
                "\(state.name(forProjectID: session.projectID) ?? "no project") · \(session.status) · \(formatAge(session.ageSeconds))"
            )
            .foregroundStyle(.secondary)
        }
    }
}
