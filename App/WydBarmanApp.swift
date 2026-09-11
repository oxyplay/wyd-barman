import AppKit
import SwiftUI

@main
struct WydBarmanApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            menuIcon()
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

    /// Template icon at a fixed size: `MenuBarExtra`'s SwiftUI `Image` label
    /// ignores parent `.frame` sizing (it sizes to the asset), so size the
    /// underlying `NSImage` directly. Template mode keeps dark/light correct.
    private func menuIcon() -> Image {
        let alert = (state.snapshot?.leftovers.count ?? 0) > 0
        guard let nsImage = NSImage(named: alert ? "MenuBarIconAlert" : "MenuBarIcon") else {
            return Image(systemName: "wineglass")
        }
        nsImage.isTemplate = true
        nsImage.size = NSSize(width: 16, height: 16)
        return Image(nsImage: nsImage)
    }
}
