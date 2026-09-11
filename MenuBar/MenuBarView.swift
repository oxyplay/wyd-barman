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

// MARK: - Action icon map

enum ActionIcon {
    static func symbol(_ token: String) -> String {
        switch token {
        case "open": "arrow.up.right"
        case "start": "play.fill"
        case "stop": "stop.fill"
        case "restart": "arrow.clockwise"
        default: "circle"
        }
    }

    static func help(_ token: String) -> String {
        switch token {
        case "open": "Open"
        case "start": "Start"
        case "stop": "Stop"
        case "restart": "Restart"
        default: token
        }
    }
}

/// Compact window-style panel (`.menuBarExtraStyle(.window)`). Rows are
/// single-line with always-visible SF Symbol action buttons built verbatim
/// from the engine's `actions` array — no hover-reveal plumbing, so mouse
/// movement never rebuilds the tree. Force Kill lives in the context menu.
struct MenuBarView: View {
    @Bindable var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var locateError: String?

    private let rowHeight: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(width: 300)
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
                                    .padding(.horizontal, 4)
                            }
                        }
                        let services = snapshot.resources.filter {
                            ["database", "dev_service", "service"].contains($0.kind)
                        }
                        if !services.isEmpty {
                            sectionHeader("SERVICES")
                            ForEach(services) { resource in
                                ResourceRowView(state: state, resource: resource)
                                    .padding(.horizontal, 4)
                            }
                        }
                        if !snapshot.containers.isEmpty {
                            sectionHeader("DOCKER")
                            ForEach(snapshot.containers) { container in
                                ContainerRowView(state: state, container: container)
                                    .padding(.horizontal, 4)
                            }
                        }
                        sectionHeader("AGENTS")
                        let active = snapshot.sessions.filter { $0.status != "ended" }
                        if active.isEmpty {
                            Text("No active sessions")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                                .frame(height: rowHeight, alignment: .leading)
                        } else {
                            ForEach(active.prefix(10)) { session in
                                SessionRowView(state: state, session: session)
                                    .padding(.horizontal, 4)
                            }
                            let ended = snapshot.sessions.filter { $0.status == "ended" }.count
                            if ended > 0 {
                                Text("+ \(ended) ended")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                    .frame(height: 16)
                            }
                        }
                        sectionHeader("LEFTOVERS")
                        leftovers(snapshot: snapshot)
                    }
                }
            }
        }
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

    @ViewBuilder
    private func leftovers(snapshot: Snapshot) -> some View {
        if snapshot.leftovers.count == 0 {
            Text("Nothing left behind")
                .foregroundStyle(.secondary)
                .font(.callout)
                .frame(height: rowHeight, alignment: .leading)
        } else {
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
        }
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

// MARK: - Row: plain button row with trailing icon actions

/// A label (dot + name + right port/status) plus always-visible SF Symbol
/// action buttons, built from the engine's `actions` array. Optional context
/// menu for kill/details.
private struct RowLayout<Label: View, Actions: View>: View {
    private let label: Label
    private let actions: Actions

    init(
        @ViewBuilder label: () -> Label,
        @ViewBuilder actions: () -> Actions
    ) {
        self.label = label()
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 4) {
            label
            Spacer(minLength: 6)
            actions
        }
        .frame(height: 24)
    }
}

struct ResourceRowView: View {
    @Bindable var state: AppState
    let resource: Resource

    var body: some View {
        RowLayout {
            HStack(spacing: 5) {
                Text("●").font(.caption2)
                Text(resource.name).lineLimit(1).truncationMode(.middle)
            }
            if let port = resource.port {
                Text(":\(port)")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        } actions: {
            ForEach(resource.actions, id: \.self) { token in
                if token == "open", let urlString = resource.url, let url = URL(string: urlString) {
                    icon("arrow.up.right", "Open") { NSWorkspace.shared.open(url) }
                } else if let action = ResourceAction(rawValue: token), action != .open,
                    action != .kill
                {
                    icon(ActionIcon.symbol(token), ActionIcon.help(token)) {
                        Task {
                            await state.perform(
                                target: resource.id, action: action, displayName: resource.name)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .contextMenu {
            ForEach(resource.actions, id: \.self) { token in
                if token == "open", let urlString = resource.url, let url = URL(string: urlString) {
                    Button("Open") { NSWorkspace.shared.open(url) }
                } else if let action = ResourceAction(rawValue: token), action != .open {
                    Button(ActionIcon.help(token)) {
                        Task {
                            await state.perform(
                                target: resource.id, action: action, displayName: resource.name)
                        }
                    }
                }
            }
            if resource.actions.contains("kill") {
                Divider()
                Button("Force Kill…", role: .destructive) {
                    Task {
                        await state.perform(
                            target: resource.id, action: .kill, displayName: resource.name)
                    }
                }
            }
            if let pid = resource.pid {
                Divider()
                Text("PID \(pid) · \(formatBytes(resource.memoryBytes))")
            }
        }
    }

    private func icon(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.borderless)
        .help(help)
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
                HStack(spacing: 5) {
                    Text("·").font(.caption2).foregroundStyle(.secondary)
                    Text(resource.name).lineLimit(1).truncationMode(.middle)
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
                Text(project.name)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Text(formatBytes(project.memoryBytes))
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Button {
                    stopTapped()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help("Stop project")
            }
        }
        .font(.callout)
        .padding(.horizontal, 4)
        .confirmationDialog(
            "Stop \(project.name)?",
            isPresented: $confirmingStop,
            titleVisibility: .visible
        ) {
            Button("Stop", role: .destructive) { stop() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(project.resourceCount) resources · \(formatBytes(project.memoryBytes))")
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

struct ContainerRowView: View {
    @Bindable var state: AppState
    let container: Container

    var body: some View {
        RowLayout {
            HStack(spacing: 5) {
                Text("●").font(.caption2)
                Text(container.name).lineLimit(1).truncationMode(.middle)
            }
            Text(container.status)
                .foregroundStyle(.secondary)
                .font(.callout)
        } actions: {
            ForEach(container.actions, id: \.self) { token in
                if let action = ResourceAction(rawValue: token) {
                    Button {
                        Task {
                            await state.perform(
                                target: container.id, action: action, displayName: container.name)
                        }
                    } label: {
                        Image(systemName: ActionIcon.symbol(token))
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.borderless)
                    .help(ActionIcon.help(token))
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

struct SessionRowView: View {
    @Bindable var state: AppState
    let session: Session

    var body: some View {
        HStack {
            Text(session.agent)
                .lineLimit(1)
            Spacer()
            Text("\(state.name(forProjectID: session.projectID) ?? "—") · \(formatAge(session.ageSeconds))")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(height: 24)
        .padding(.horizontal, 4)
    }
}