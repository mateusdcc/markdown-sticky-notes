import AppKit
import SwiftUI

struct SettingsView: View {
    let coordinator: AppCoordinator
    var body: some View { EmptyView() }
}

@main
struct NoteInteractionTests {
    static func main() {
        testPinnedNoteClickThroughAndFocus()
        testOpacitySettingsPersistAndClamp()
        print("Click-through, pinning, focus, and opacity persistence checks passed.")
    }
    static func testPinnedNoteClickThroughAndFocus() {
        _ = NSApplication.shared
        let controller = NoteWindowController(note: Note(opacity: 0.9, alwaysOnTop: true), coordinator: nil)
        let window = controller.window!

        controller.refreshInteraction(optionHeld: false)
        assert(window.ignoresMouseEvents)
        controller.refreshInteraction(optionHeld: true)
        assert(!window.ignoresMouseEvents)
        controller.refreshInteraction(optionHeld: false)
        assert(window.ignoresMouseEvents)

        controller.setAlwaysOnTop(false)
        assert(!window.ignoresMouseEvents)
        controller.setOpacity(0.7)
        assert(abs(window.alphaValue - 0.7) < 0.001)

        // A key panel must still pass clicks through when its app is inactive.
        controller.setAlwaysOnTop(true)
        window.becomeKey()
        controller.refreshInteraction(optionHeld: false)
        assert(window.ignoresMouseEvents == !NSApp.isActive)
        if NSApp.isActive {
            assert(abs(window.alphaValue - 0.7) < 0.001)
        }
        window.resignKey()
        controller.refreshInteraction(optionHeld: false)
        assert(window.ignoresMouseEvents)
    }

    static func testOpacitySettingsPersistAndClamp() {
        let suite = "StickyNotesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = PersistenceManager(userDefaults: defaults)
        assert(persistence.loadOpacity("unfocusedOpacity", default: 0.55) == 0.55)
        persistence.saveOpacity(0.4, forKey: "unfocusedOpacity")
        persistence.saveOpacity(0.95, forKey: "focusedOpacity")
        let reloaded = PersistenceManager(userDefaults: defaults)
        assert(reloaded.loadOpacity("unfocusedOpacity", default: 1) == 0.4)
        assert(reloaded.loadOpacity("focusedOpacity", default: 1) == 0.95)
        persistence.saveOpacity(0, forKey: "unfocusedOpacity")
        assert(reloaded.loadOpacity("unfocusedOpacity", default: 1) == 0.2)
        defaults.set(Double.nan, forKey: "unfocusedOpacity")
        assert(reloaded.loadOpacity("unfocusedOpacity", default: 0.55) == 0.55)
    }
}
