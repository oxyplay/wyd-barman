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

/// Compact window-style panel (`.menuBarExtraStyle(.window)`). Rows are
/// single-line; primary actions (open / stop / start / restart) reveal on
/// hover for one-click access; Force Kill sits in a per-row menu.
struct MenuBarView: View {
    @Bindable var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var locateError: String?
    @State private var hoveredID: String?

    private let rowHeight: CGFloat = 22

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(width: 320)
        .task {
            await state.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await state.refresh()
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let banner = state.errorBanner {
                        bannerRow(banner)
                    }
                    if let snapshot = state.snapshot {
                        if !snapshot.projects.isEmpty {
                            sectionHeader("PROJECTS")
                            ForEach(snapshot.projects) { project in
                                ProjectRowView(state: state, project: project)
                                    .padding(.horizontal, 2)
                            }
                        }
                        let services = snapshot.resources.filter {
                            ["database", "dev_service", "service"].contains($0.kind)
                        }
                        if !services.isEmpty {
                            sectionHeader("SERVICES")
                            ForEach(services) { resource in
                                ResourceRowView(
                                    state: state, resource: resource, hoveredID: $hoveredID)
                                    .padding(.horizontal, 2)
                            }
                        }
                        if !snapshot.containers.isEmpty {
                            sectionHeader("DOCKER")
                            ForEach(snapshot.containers) { container in
                                ContainerRowView(
                                    state: state, container: container, hoveredID: $hoveredID)
                                    .padding(.horizontal, 2)
                            }
                        }
                        let active = activeSessions(snapshot)
                        sectionHeader("AGENTS")
                        if active.isEmpty {
                            Text("No active sessions")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                                .frame(height: rowHeight)
                        } else {
                            ForEach(active.prefix(10)) { session in
                                SessionRowView(state: state, session: session)
                                    .padding(.horizontal, 2)
                            }
                            let ended = snapshot.sessions.filter { $0.status == "ended" }.count
                            if ended > 0 {
                                Text("+ \(ended) ended")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                    .frame(height: 18)
                            }
                        }
                        sectionHeader("LEFTOVERS")
                        leftovers(snapshot: snapshot)
                    }
                }
            }
        }
    }

    private func activeSessions(_ snapshot: Snapshot) -> [Session] {
        snapshot.sessions.filter { $0.status != "ended" }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .kerning(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func bannerRow(_ text: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
            Text(text)
            Spacer()
            if let detail = state.errorDetail {
                Text(detail)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlColor))
    }

    private func leftovers(snapshot: Snapshot) -> some View {
        if snapshot.leftovers.count == 0 {
            return AnyView(
                Text("Nothing left behind")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(height: rowHeight, alignment: .leading)
            )
        }
        return AnyView(
            HStack {
                Text(
                    "\(snapshot.leftovers.count) · \(formatBytes(snapshot.leftovers.estimatedReclaimBytes))"
                )
                Spacer()
                Button("Review") {
                    Task { await state.fetchCleanupPlan() }
                    openWindow(id: "cleanup")
                }
                .controlSize(.small)
            }
            .frame(height: rowHeight)
        )
    }

    // MARK: - Engine states

    private var missingWyd: some View {
        VStack(spacing: 8) {
            Text("wyd not found")
                .fontWeight(.medium)
            Text("wyd-barman requires the wyd engine.")
                .foregroundStyle(.secondary)
            HStack {
                Link("Install wyd", destination: WydLocator.installURL)
                Button("Locate…") { locateBinary() }
            }
            if let locateError {
                Text(locateError)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(20)
    }

    private var incompatibleWyd: some View {
        VStack(spacing: 8) {
            Text("wyd needs to be updated")
                .fontWeight(.medium)
            if let detail = state.errorDetail {
                Text(detail)
                    .foregroundStyle(.secondary)
            }
            Button("Check again") {
                Task { await state.refresh() }
            }
        }
        .padding(20)
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
        HStack {
            Button("Refresh") { Task { await state.refresh() } }
            Spacer()
            if let last = state.lastRefresh {
                Text("\(formatAge(UInt64(Date().timeIntervalSince(last))))")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            SettingsLink()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

// MARK: - Rows

/// One-line row: `● name` + right-aligned `:port`; primary action buttons
/// appear inline on hover, built verbatim from the engine's `actions` array.
struct ResourceRowView: View {
    @Bindable var state: AppState
    let resource: Resource
    @Binding var hoveredID: String?
    @State private var confirmingKill = false

    var body: some View {
        HStack(spacing: 6) {
            Text("●")
                .font(.caption)
            Text(resource.name)
                .lineLimit(1)
            Spacer()
            if let port = resource.port {
                Text(":\(port)")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            if hoveredID == resource.id {
                HStack(spacing: 2) {
                    ForEach(primaryActions, id: \.self) { token in
                        actionButton(token)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(isHovered ? Color(nsColor: .controlAccentColor).opacity(0.12) : Color.clear)
        .cornerRadius(4)
        .onHover { hovering in
            hoveredID = hovering ? resource.id : nil
        }
        .contextMenu {
            contextItems
        }
        .confirmationDialog(
            "Force kill \(resource.name)?",
            isPresented: $confirmingKill,
            titleVisibility: .visible
        ) {
            Button("Force Kill", role: .destructive) {
                Task {
                    await state.perform(
                        target: resource.id, action: .kill, displayName: resource.name)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var isHovered: Bool { hoveredID == resource.id }

    /// Open (if url) + start/stop/restart as supplied by the engine. Kill is
    /// reserved for the context menu with confirmation.
    private var primaryActions: [String] {
        resource.actions.filter { $0 != "kill" }
    }

    @ViewBuilder
    private func actionButton(_ token: String) -> some View {
        if token == "open", let urlString = resource.url, let url = URL(string: urlString) {
            smallButton("arrow.up.right.circle", help: "Open") { NSWorkspace.shared.open(url) }
        } else if let action = ResourceAction(rawValue: token), action != .open, action != .kill {
            let icon = action == .stop ? "stop.circle"
                : action == .start ? "play.circle" : "arrow.clockwise.circle"
            smallButton(icon, help: actionLabel(action)) {
                Task {
                    await state.perform(
                        target: resource.id, action: action, displayName: resource.name)
                }
            }
        }
    }

    private func smallButton(
        _ systemName: String, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private var contextItems: some View {
        Group {
            ForEach(primaryActions, id: \.self) { token in
                if token == "open", let urlString = resource.url, let url = URL(string: urlString) {
                    Button("Open") { NSWorkspace.shared.open(url) }
                } else if let action = ResourceAction(rawValue: token), action != .open,
                    action != .kill
                {
                    Button(actionLabel(action)) {
                        Task {
                            await state.perform(
                                target: resource.id, action: action, displayName: resource.name)
                        }
                    }
                }
            }
            if resource.actions.contains("kill") {
                Divider()
                Button("Force Kill…", role: .destructive) { confirmingKill = true }
            }
            if let pid = resource.pid {
                Divider()
                Text("PID \(pid) · \(formatBytes(resource.memoryBytes))")
            }
        }
    }

    private func actionLabel(_ action: ResourceAction) -> String {
        switch action {
        case .open: "Open"
        case .start: "Start"
        case .stop: "Stop"
        case .restart: "Restart"
        case .kill: "Force Kill"
        }
    }
}

struct ProjectRowView: View {
    @Bindable var state: AppState
    let project: Project
    @State private var confirmingStop = false

    private var confirmStop: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.confirmProjectStop) as? Bool ?? true
    }

    var body: some View {
        DisclosureGroup {
            ForEach(state.members(of: project)) { resource in
                HStack(spacing: 6) {
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(resource.name).lineLimit(1)
                    Spacer()
                    if let port = resource.port {
                        Text(":\(port)").foregroundStyle(.secondary).font(.callout)
                    }
                }
                .padding(.leading, 14)
                .frame(height: 20)
            }
        } label: {
            HStack {
                Text("\(project.name)")
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Text(formatBytes(project.memoryBytes))
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Button("Stop") { stopTapped() }
                    .controlSize(.small)
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
            }
        }
        .font(.callout)
        .padding(.horizontal, 6)
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

struct ContainerRowView: View {
    @Bindable var state: AppState
    let container: Container
    @Binding var hoveredID: String?

    var body: some View {
        HStack(spacing: 6) {
            Text("●")
                .font(.caption)
            Text(container.name).lineLimit(1)
            Spacer()
            Text(container.status)
                .foregroundStyle(.secondary)
                .font(.callout)
            ForEach(primaryActions, id: \.self) { token in
                if let action = ResourceAction(rawValue: token) {
                    Button(
                        action == .start ? "Start" : action == .stop ? "Stop" : "Restart"
                    ) {
                        Task {
                            await state.perform(
                                target: container.id, action: action, displayName: container.name)
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
    }

    private var primaryActions: [String] {
        container.actions
    }
}

struct SessionRowView: View {
    @Bindable var state: AppState
    let session: Session

    var body: some View {
        HStack {
            Text("\(session.agent)")
                .lineLimit(1)
            Spacer()
            Text(
                "\(state.name(forProjectID: session.projectID) ?? "—") · \(formatAge(session.ageSeconds))"
            )
            .foregroundStyle(.secondary)
            .font(.callout)
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
    }
}
