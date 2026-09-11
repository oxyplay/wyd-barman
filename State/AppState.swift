import Foundation

enum RefreshFrequency: String, CaseIterable {
    case auto = "Auto"
    case frequent = "Frequent"
    case paused = "Paused"

    /// Menu-closed background interval. The open menu refreshes every 3s
    /// from the view itself; both paths share the `inFlight` guard.
    var backgroundInterval: TimeInterval? {
        switch self {
        case .auto: 20
        case .frequent: 5
        case .paused: nil
        }
    }
}

enum SettingsKeys {
    static let refreshFrequency = "refreshFrequency"
    static let confirmProjectStop = "confirmProjectStop"
    static let confirmCleanup = "confirmCleanup"
}

/// Cached `wyd` snapshot plus refresh policy. Menu content renders this
/// cache instantly; refreshes happen asynchronously and never overlap.
@Observable
@MainActor
final class AppState {
    var snapshot: Snapshot?
    var lastRefresh: Date?
    var inFlight = false
    var errorBanner: String?
    var errorDetail: String?
    var cleanupPlan: CleanupPlan?
    var cleanupSelection = Set<String>()
    var wydVersion: String?

    nonisolated let client: any WydClient

    init(client: any WydClient = ProcessWydClient()) {
        self.client = client
        if UserDefaults.standard.string(forKey: SettingsKeys.refreshFrequency) == nil {
            UserDefaults.standard.set(RefreshFrequency.auto.rawValue, forKey: SettingsKeys.refreshFrequency)
        }
        // Closed-menu refresh keeps the cached snapshot warm (20s/5s/off);
        // the open menu drives its own 3s loop via `.task`.
        Task { await startBackgroundRefresh() }
    }

    var frequency: RefreshFrequency {
        get {
            RefreshFrequency(
                rawValue: UserDefaults.standard.string(forKey: SettingsKeys.refreshFrequency) ?? ""
            ) ?? .auto
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: SettingsKeys.refreshFrequency) }
    }

    /// Closed-menu background refresh: every `frequency` interval, unless
    /// Paused. The open-menu loop drives its own 3s refreshes; `inFlight`
    /// drops any overlap between the two.
    func startBackgroundRefresh() async {
        while !Task.isCancelled {
            if let interval = frequency.backgroundInterval {
                try? await Task.sleep(for: .seconds(interval))
                await refresh()
            } else {
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func refresh() async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        do {
            let snap = try await client.snapshot()
            snapshot = snap
            lastRefresh = Date()
            errorBanner = nil
            errorDetail = nil
        } catch let error as WydError {
            present(error)
        } catch {
            errorBanner = "Could not refresh."
            errorDetail = error.localizedDescription
        }
    }

    func perform(target: String, action: ResourceAction, displayName: String) async {
        do {
            _ = try await client.perform(target: target, action: action)
            await refresh()
        } catch WydError.staleTarget {
            // Engine reports the id no longer resolves: re-refresh so the
            // menu stops showing the dead row.
            await refresh()
        } catch let error as WydError {
            errorBanner = "Could not \(action.verb) \(displayName)."
            errorDetail = error.errorDescription
        } catch {
            errorBanner = "Could not \(action.verb) \(displayName)."
            errorDetail = error.localizedDescription
        }
    }

    func fetchCleanupPlan() async {
        do {
            let plan = try await client.cleanupPlan()
            cleanupPlan = plan
            cleanupSelection = Set(plan.items.map(\.resourceID))
            errorBanner = nil
            errorDetail = nil
        } catch let error as WydError {
            present(error)
        } catch {
            errorBanner = "Could not load cleanup plan."
            errorDetail = error.localizedDescription
        }
    }

    func executeCleanup() async {
        guard let plan = cleanupPlan else { return }
        let all = Set(plan.items.map(\.resourceID))
        let only = cleanupSelection == all ? nil : Array(cleanupSelection)
        do {
            _ = try await client.executeCleanup(planID: plan.planID, only: only)
            cleanupPlan = nil
            cleanupSelection = []
            await refresh()
        } catch let error as WydError {
            present(error)
        } catch {
            errorBanner = "Cleanup failed."
            errorDetail = error.localizedDescription
        }
    }

    func checkVersion() async {
        do {
            wydVersion = try await client.apiVersion().wydVersion
        } catch {
            wydVersion = nil
        }
    }

    // MARK: - Derived

    func members(of project: Project) -> [Resource] {
        (snapshot?.resources ?? [])
            .filter { $0.projectID == project.id }
            .sorted { $0.name < $1.name }
    }

    func name(forProjectID id: String?) -> String? {
        guard let id else { return nil }
        return snapshot?.projects.first { $0.id == id }?.name
    }

    func name(forResourceID id: String) -> String? {
        if let r = snapshot?.resources.first(where: { $0.id == id }) { return r.name }
        if let c = snapshot?.containers.first(where: { $0.id == id }) { return c.name }
        return nil
    }

    // MARK: - Errors (non-modal banner rows, never alerts)

    private func present(_ error: WydError) {
        switch error {
        case .notFound:
            errorBanner = "wyd not found"
            errorDetail = "wyd-barman requires the wyd engine."
        case .incompatible(let version):
            errorBanner = "wyd needs to be updated"
            errorDetail = version.map { "Installed wyd \($0) speaks a different schema." }
        case .timeout(let what):
            // Keep the cached snapshot; a hung engine must not blank the menu.
            errorBanner = "\(what) timed out."
            errorDetail = "The menu still shows the last good snapshot."
        case .actionFailed(let summary, let detail):
            errorBanner = summary
            errorDetail = detail
        case .decodeFailed(let detail):
            errorBanner = "Could not read wyd output."
            errorDetail = detail
        case .staleTarget:
            errorBanner = "That resource changed. Refreshed."
            errorDetail = nil
        }
    }
}
