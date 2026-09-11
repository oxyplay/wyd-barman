import SwiftUI

@main
struct WydBarmanApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            // Explicit 14pt frame: the asset's transparent padding is ignored
            // by the menu bar, so glyph size is controlled here, not by SVG
            // viewBox.
            Group {
                if (state.snapshot?.leftovers.count ?? 0) > 0 {
                    Image("MenuBarIconAlert")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image("MenuBarIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: 14, height: 14)
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
