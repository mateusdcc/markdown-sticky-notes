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
        testStackedOpacityControls()
        print("Click-through, pinning, focus, and opacity persistence checks passed.")
    }
    static func testPinnedNoteClickThroughAndFocus() {
        _ = NSApplication.shared
        let controller = NoteWindowController(note: Note(opacity: 0.9, alwaysOnTop: true), coordinator: nil)
        let window = controller.window!
        assert(window.styleMask.contains(.nonactivatingPanel))
        assert(window.collectionBehavior.contains(.canJoinAllSpaces))

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

        // A nonactivating panel can accept typing while its app stays inactive.
        controller.setAlwaysOnTop(true)
        assert(window.styleMask.contains(.nonactivatingPanel))
        assert(window.collectionBehavior.contains(.canJoinAllSpaces))
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        controller.focus()
        controller.refreshInteraction(optionHeld: false)
        assert(window.isKeyWindow)
        assert(!window.ignoresMouseEvents)
        assert(abs(window.alphaValue - 0.7) < 0.001)
        assert(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostPID)
        window.resignKey()
        controller.refreshInteraction(optionHeld: false)
        assert(window.ignoresMouseEvents)
    }

    static func testStackedOpacityControls() {
        let note = Note(opacity: 0.9, unfocusedOpacity: 0.4, alwaysOnTop: true)
        let controller = NoteWindowController(note: note, coordinator: nil)
        let window = controller.window!
        let controls = window.titlebarAccessoryViewControllers[0].view.subviews.compactMap { $0 as? NSSlider }
        assert(controls.count == 2)
        assert(controls.allSatisfy { $0.sliderType == .linear })
        assert(controls[0].frame.minY >= controls[1].frame.maxY)
        assert(controls[0].frame.minX == controls[1].frame.minX)
        assert(controls[0].frame.width == 50 && controls[1].frame.width == 50)
        assert(controls[0].doubleValue == 0.9 && controls[1].doubleValue == 0.4)
        controls[0].doubleValue = 0.8
        controls[0].sendAction(controls[0].action, to: controls[0].target)
        controls[1].doubleValue = 0.3
        controls[1].sendAction(controls[1].action, to: controls[1].target)
        controller.focus()
        controller.refreshInteraction(optionHeld: false)
        assert(abs(window.alphaValue - 0.8) < 0.001)
        let orange = controls[1] as! OpacitySlider
        orange.setTrackingOpacity(true)
        controller.refreshInteraction(optionHeld: false) // The periodic refresh must preserve preview.
        assert(abs(window.alphaValue - 0.3) < 0.001)
        assert(!window.ignoresMouseEvents)
        orange.doubleValue = 0.45
        _ = orange.sendAction(orange.action, to: orange.target)
        assert(abs(window.alphaValue - 0.45) < 0.001)
        let hint = NSApp.windows.first { panel in
            panel.contentView?.subviews.contains { view in
                (view as? NSTextField)?.stringValue == "Changing opacity of unfocused… 45%"
            } == true
        }
        assert(hint?.isVisible == true && hint?.ignoresMouseEvents == true)
        assert(window.isKeyWindow)
        orange.setTrackingOpacity(false)
        assert(hint?.isVisible == false)
        assert(abs(window.alphaValue - 0.8) < 0.001)
        window.resignKey()
        controller.refreshInteraction(optionHeld: false)
        assert(abs(window.alphaValue - 0.45) < 0.001)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try! encoder.encode(note)
        assert(try! decoder.decode(Note.self, from: data).unfocusedOpacity == 0.4)
        var legacy = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        legacy.removeValue(forKey: "unfocusedOpacity")
        let legacyData = try! JSONSerialization.data(withJSONObject: legacy)
        assert(try! decoder.decode(Note.self, from: legacyData).unfocusedOpacity == nil)
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
