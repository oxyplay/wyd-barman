import Foundation

enum SettingsKeys {
    static let confirmProjectStop = "confirmProjectStop"
    static let confirmCleanup = "confirmCleanup"
    static let preventSleep = "preventSleep"
    static let demoMode = "demoMode"
}

/// Cached `wyd` snapshot plus refresh policy. Refresh happens on menu open
/// and every 10s while open; a light background poll (3 min) keeps the
/// cache fresh while closed. `inFlight` never lets them overlap.
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
    var preventSleep = UserDefaults.standard.bool(forKey: SettingsKeys.preventSleep) {
        didSet {
            UserDefaults.standard.set(preventSleep, forKey: SettingsKeys.preventSleep)
            SleepPreventer.shared.setActive(preventSleep)
        }
    }

    /// Routes every engine call through the deterministic demo dataset.
    var demoMode = UserDefaults.standard.bool(forKey: SettingsKeys.demoMode) {
        didSet {
            UserDefaults.standard.set(demoMode, forKey: SettingsKeys.demoMode)
        }
    }

    nonisolated let client: any WydClient

    init(client: any WydClient = ProcessWydClient()) {
        self.client = client
        if UserDefaults.standard.bool(forKey: SettingsKeys.preventSleep) {
            SleepPreventer.shared.setActive(true)
        }
        // Closed-menu background poll: every 3 minutes, so opening the menu
        // shows fresh-enough data instantly. The open menu refreshes on open
        // + every 10s; `inFlight` drops overlaps.
        Task { await startBackgroundRefresh() }
    }

    func startBackgroundRefresh() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(180))
            await refresh()
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
            // Engine decides: only selected + safe rows are pre-checked.
            cleanupSelection = Set(
                plan.items
                    .filter { $0.selected && $0.safe }
                    .map(\.resourceID))
            errorBanner = nil
            errorDetail = nil
        } catch let error as WydError {
            present(error)
        } catch {
            errorBanner = "Could not load cleanup plan."
            errorDetail = error.localizedDescription
        }
    }

    /// Returns true on success; on failure the caller should keep the sheet
    /// open — the error is surfaced in the banner.
    func executeCleanup() async -> Bool {
        guard let plan = cleanupPlan else { return false }
        let all = Set(plan.items.map(\.resourceID))
        let only = cleanupSelection == all ? nil : Array(cleanupSelection)
        do {
            _ = try await client.executeCleanup(planID: plan.planID, only: only)
        } catch {
            if let e = error as? WydError {
                present(e)
            } else {
                errorBanner = "Cleanup failed."
                errorDetail = error.localizedDescription
            }
            return false
        }
        cleanupPlan = nil
        cleanupSelection = []
        await refresh()
        return true
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
