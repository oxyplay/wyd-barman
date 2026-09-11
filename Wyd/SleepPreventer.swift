import Foundation
import IOKit.pwr_mgt

/// Prevents the Mac from idling to sleep and from starting the screen saver,
/// via the native `IOPMAssertion` API (no external process). Toggle on/off.
final class SleepPreventer: @unchecked Sendable {
    static let shared = SleepPreventer()
    /// One assertion per type: system sleep AND display sleep / screen saver.
    private var assertionIDs: [IOPMAssertionID] = []
    private var active = false

    private init() {}

    /// All public calls are MainActor-confined via AppState; the mutable
    /// assertion state needs no cross-thread sync.
    @MainActor
    var isActive: Bool { active }

    /// Takes assertions to keep the system and the display awake while `on`.
    @MainActor
    func setActive(_ on: Bool) {
        guard on != active else { return }
        if on {
            start()
        } else {
            stop()
        }
    }

    @MainActor
    private func start() {
        guard !active else { return }
        let reason = "wyd-barman: keep awake" as CFString
        for kind in [kIOPMAssertionTypeNoIdleSleep, kIOPMAssertionTypeNoDisplaySleep] {
            var assertion = IOPMAssertionID(0)
            let ok = IOPMAssertionCreateWithName(
                kind as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &assertion
            )
            if ok == kIOReturnSuccess {
                assertionIDs.append(assertion)
            }
        }
        active = !assertionIDs.isEmpty
    }

    @MainActor
    private func stop() {
        guard active else { return }
        for id in assertionIDs {
            IOPMAssertionRelease(id)
        }
        assertionIDs = []
        active = false
    }
}