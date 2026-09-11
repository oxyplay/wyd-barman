import SwiftUI

@main
struct WydBarmanApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            if (state.snapshot?.leftovers.count ?? 0) > 0 {
                Image("MenuBarIconAlert")
            } else {
                Image("MenuBarIcon")
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(state: state)
        }

        Window("Cleanup Review", id: "cleanup") {
            CleanupView(state: state)
        }
        .windowResizability(.contentSize)
    }
}
