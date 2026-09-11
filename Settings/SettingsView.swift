import AppKit
import ServiceManagement
import SwiftUI

/// Minimal settings: launch at login, keep-awake, engine binary, and
/// confirmation behavior. No discovery/ownership/cleanup rules — those
/// belong in `wyd`. (Refresh is fixed: on open + every 10s while open.)
struct SettingsView: View {
    @Bindable var state: AppState
    @AppStorage(SettingsKeys.confirmProjectStop) private var confirmProjectStop = true
    @AppStorage(SettingsKeys.confirmCleanup) private var confirmCleanup = true
    @AppStorage(WydLocator.overrideKey) private var binaryPath = ""
    @State private var loginError: String?
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        // Plain layout sized to content: the grouped Form overflowed the
        // settings window and showed a scrollbar.
        VStack(alignment: .leading, spacing: 14) {
            settingTitle("General")
            Toggle("Launch at Login", isOn: $loginEnabled)
                .onChange(of: loginEnabled) { _, on in
                    setLogin(enabled: on)
                }
            if let loginError {
                Text(loginError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            Toggle("Keep Mac awake (no sleep / no screen saver)", isOn: $state.preventSleep)
            Toggle(
                "Demo mode (synthetic data, safe to click around)",
                isOn: $state.demoMode)

            Divider()
            settingTitle("wyd")
            HStack {
                TextField("/opt/homebrew/bin/wyd", text: $binaryPath)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") { chooseBinary() }
                if !binaryPath.isEmpty {
                    Button("Clear") { binaryPath = "" }
                }
            }
            HStack {
                Text("Version")
                Spacer()
                Text(state.wydVersion ?? "unknown").foregroundStyle(.secondary)
            }

            Divider()
            settingTitle("Behavior")
            Toggle("Confirm project stop", isOn: $confirmProjectStop)
            Toggle("Confirm cleanup", isOn: $confirmCleanup)
        }
        .toggleStyle(.switch)
        .padding(20)
        .frame(width: 420, alignment: .leading)
        .task {
            await state.checkVersion()
        }
        .onChange(of: binaryPath) {
            Task { await state.checkVersion() }
        }
    }

    private func settingTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
    }

    private func setLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            loginEnabled = SMAppService.mainApp.status == .enabled
        }
    }

    private func chooseBinary() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            binaryPath = url.path
        }
    }
}
