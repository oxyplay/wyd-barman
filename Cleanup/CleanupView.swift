import SwiftUI

/// Renders the engine's cleanup plan: selected leftover candidates,
/// protected services, and the reclaim estimate. Deselected rows are passed
/// as an `only:` subset — still validated engine-side before execution.
struct CleanupView: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingClean = false

    private var confirmCleanup: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.confirmCleanup) as? Bool ?? true
    }

    var body: some View {
        Group {
            if let plan = state.cleanupPlan {
                planContent(plan: plan)
            } else {
                VStack(spacing: 12) {
                    Text("No cleanup plan loaded.")
                        .foregroundStyle(.secondary)
                    Button("Reload") {
                        Task { await state.fetchCleanupPlan() }
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 360)
        .task {
            if state.cleanupPlan == nil {
                await state.fetchCleanupPlan()
            }
        }
    }

    private func planContent(plan: CleanupPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cleanup Review")
                .font(.headline)
            ForEach(plan.items) { item in
                Toggle(
                    isOn: Binding(
                        get: { state.cleanupSelection.contains(item.resourceID) },
                        set: { on in
                            if on {
                                state.cleanupSelection.insert(item.resourceID)
                            } else {
                                state.cleanupSelection.remove(item.resourceID)
                            }
                        }
                    )
                ) {
                    HStack {
                        Text(state.name(forResourceID: item.resourceID) ?? item.resourceID)
                        Spacer()
                        Text(item.reason)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !plan.protected.isEmpty {
                Divider()
                Text("Protected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(plan.protected) { item in
                    HStack {
                        Text(state.name(forResourceID: item.resourceID) ?? item.resourceID)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(item.reason)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            Text(reclaimText(plan))
            .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Clean") { cleanTapped() }
                    .disabled(state.cleanupSelection.isEmpty)
                    .confirmationDialog(
                        "Clean \(state.cleanupSelection.count) resources?",
                        isPresented: $confirmingClean,
                        titleVisibility: .visible
                    ) {
                        Button("Clean", role: .destructive) { clean() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(reclaimText(plan))
                    }
            }
        }
        .padding(20)
    }

    private func reclaimText(_ plan: CleanupPlan) -> String {
        plan.estimatedReclaimBytes > 0
            ? "Estimated reclaim: \(formatBytes(plan.estimatedReclaimBytes))"
            : "Estimated reclaim: unknown (engine reported no sizes)"
    }


    private func cleanTapped() {
        if confirmCleanup {
            confirmingClean = true
        } else {
            clean()
        }
    }

    private func clean() {
        Task {
            // Keep the sheet open on failure so the banner is actually seen.
            if await state.executeCleanup() {
                dismiss()
            }
        }
    }
}
