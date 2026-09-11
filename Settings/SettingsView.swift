import AppKit
import ServiceManagement
import SwiftUI

/// Minimal settings: launch at login, keep-awake, demo mode, engine binary,
/// and confirmation behavior. No discovery/ownership/cleanup rules — those
/// belong in `wyd`. Toggles are right-aligned macOS-style via LabeledContent.
struct SettingsView: View {
    @Bindable var state: AppState
    @AppStorage(SettingsKeys.confirmProjectStop) private var confirmProjectStop = true
    @AppStorage(SettingsKeys.confirmCleanup) private var confirmCleanup = true
    @AppStorage(WydLocator.overrideKey) private var binaryPath = ""
    @State private var loginError: String?
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingTitle("General")
            VStack(spacing: 10) {
                settingsRow {
                    Toggle("Launch at Login", isOn: $loginEnabled)
                        .onChange(of: loginEnabled) { _, on in
                            setLogin(enabled: on)
                        }
                }
                settingsRow {
                    Toggle("Keep Mac awake", isOn: $state.preventSleep)
                }
                settingsRow {
                    Toggle("Demo mode", isOn: $state.demoMode)
                }
                explanationRow(
                    "Keep awake: no sleep and no screen saver. Demo mode: synthetic data from the engine, safe to click around."
                )
                if let loginError {
                    Text(loginError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Divider()

            settingTitle("wyd")
            VStack(spacing: 10) {
                HStack {
                    Text("Binary")
                    Spacer()
                    Text(binaryDisplayPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(binaryDisplayPath)
                    Button("Choose…") { chooseBinary() }
                        .controlSize(.small)
                    if !binaryPath.isEmpty {
                        Button("Reset") { binaryPath = "" }
                            .controlSize(.small)
                    }
                }
                HStack {
                    Text("Version")
                    Spacer()
                    Text(state.wydVersion ?? "unknown")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            settingTitle("Behavior")
            VStack(spacing: 10) {
                settingsRow {
                    Toggle("Confirm project stop", isOn: $confirmProjectStop)
                }
                settingsRow {
                    Toggle("Confirm cleanup", isOn: $confirmCleanup)
                }
            }
        }
        .toggleStyle(.switch)
        .padding(24)
        .frame(width: 440, alignment: .leading)
        .task {
            await state.checkVersion()
        }
        .onChange(of: binaryPath) {
            Task { await state.checkVersion() }
        }
    }

    /// Row with the label left and the toggle right (standard macOS settings).
    private func settingsRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack {
            content()
            Spacer(minLength: 12)
        }
    }

    private func explanationRow(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var binaryDisplayPath: String {
        binaryPath.isEmpty ? "auto-detected" : binaryPath
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
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        if panel.runModal() == .OK, let url = panel.url {
            binaryPath = url.path
        }
    }
}