import SwiftUI
import AppKit

// MARK: - App Delegate

/// Keeps the app alive when all windows are closed and provides dock menu
class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.isQuitting = true
        coordinator.saveLastActiveNote()
        coordinator.saveAllNotesImmediately()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.restoreLastActiveNote()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let newNoteItem = NSMenuItem(
            title: "New Note",
            action: #selector(createNewNote),
            keyEquivalent: ""
        )
        newNoteItem.target = self
        menu.addItem(newNoteItem)
        return menu
    }

    @objc func createNewNote() {
        coordinator.createNewNote()
    }
}

// MARK: - App Entry Point

@main
struct StickyNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarCommands(coordinator: appDelegate.coordinator)
    }
}

// MARK: - Menu Bar

struct MenuBarCommands: Scene {
    @ObservedObject var coordinator: AppCoordinator

    var body: some Scene {
        Settings {
            SettingsView(coordinator: coordinator)
        }
        .commands {
            // App menu — Settings (Cmd+,) opens floating Settings window above sticky notes
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    coordinator.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            // File menu
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    coordinator.createNewNote()
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()

                Button("Show All Notes") {
                    coordinator.showAllNotes()
                }
            }

            // Edit menu — Find in note (Cmd+F → shared WKWebView)
            CommandGroup(replacing: .textEditing) {
                Button("Find...") {
                    if coordinator.focusedNoteId() != nil {
                        SharedWebViewManager.shared.webView.evaluateJavaScript("window.openSearch()")
                    }
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Find and Replace...") {
                    if coordinator.focusedNoteId() != nil {
                        SharedWebViewManager.shared.webView.evaluateJavaScript("window.openSearchWithReplace()")
                    }
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }

            // Window menu — Cmd+` to cycle between note windows
            CommandGroup(before: .windowList) {
                Button("Cycle Through Notes") {
                    coordinator.cycleToNextWindow()
                }
                .keyboardShortcut("`", modifiers: .command)
            }

            // Format menu
            CommandMenu("Format") {
                Menu("Note Color") {
                    ForEach(NoteColor.allCases, id: \.self) { color in
                        Button(color.displayName) {
                            if let noteId = coordinator.focusedNoteId() {
                                coordinator.changeNoteColor(noteId: noteId, colorTheme: color.rawValue)
                            }
                        }
                    }
                }

                Divider()

                Menu("Opacity") {
                    Button("100%") { setOpacity(1.0) }
                    Button("75%") { setOpacity(0.75) }
                    Button("50%") { setOpacity(0.5) }
                    Button("25%") { setOpacity(0.25) }
                }

                Divider()

                Button("Pin on Top") {
                    if let noteId = coordinator.focusedNoteId(),
                       let note = coordinator.noteManager.getNote(noteId) {
                        coordinator.setNoteAlwaysOnTop(noteId: noteId, alwaysOnTop: !note.alwaysOnTop)
                    }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Divider()

                Picker("Math Renderer", selection: Binding(
                    get: { coordinator.mathRenderer },
                    set: { coordinator.setMathRenderer($0) }
                )) {
                    ForEach(MathRenderer.allCases, id: \.self) { renderer in
                        Text(renderer.displayName).tag(renderer)
                    }
                }

                Button("Note & Math Settings...") {
                    coordinator.openSettings()
                }
            }
        }
    }

    private func setOpacity(_ opacity: Double) {
        if let noteId = coordinator.focusedNoteId() {
            coordinator.setNoteOpacity(noteId: noteId, opacity: opacity)
        }
    }

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Note Opacity").font(.headline)
            HStack {
                Text("Focused").frame(width: 90, alignment: .leading)
                Slider(value: Binding(
                    get: { coordinator.focusedOpacity },
                    set: { coordinator.setFocusedOpacity($0) }
                ), in: 0.2...1.0)
                Text(coordinator.focusedOpacity, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            HStack {
                Text("Unfocused").frame(width: 90, alignment: .leading)
                Slider(value: Binding(
                    get: { coordinator.unfocusedOpacity },
                    set: { coordinator.setUnfocusedOpacity($0) }
                ), in: 0.2...1.0)
                Text(coordinator.unfocusedOpacity, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            Text("These settings apply to all notes. Use the sun and moon knobs in a note’s titlebar to adjust it individually.")
                .font(.caption).foregroundColor(.secondary)
            Text("Unfocused pinned notes let clicks pass through. Hold Option (⌥) and click a note to focus and edit it.")
                .font(.caption).foregroundColor(.secondary)

            Divider()

            HStack(alignment: .top, spacing: 12) {
                Text("Math Renderer:")
                    .fontWeight(.medium)
                    .frame(width: 130, alignment: .trailing)

                Picker("", selection: Binding(
                    get: { coordinator.mathRenderer },
                    set: { coordinator.setMathRenderer($0) }
                )) {
                    ForEach(MathRenderer.allCases, id: \.self) { renderer in
                        Text(renderer.displayName).tag(renderer)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Custom Overhead (Preamble):")
                        .fontWeight(.medium)
                    Spacer()
                    Button("Reset Default") {
                        coordinator.setMathPreamble(PersistenceManager.defaultMathPreamble)
                    }
                    .controlSize(.small)
                }

                Text("Typst definitions (#let, #set, #show) prepended to every math equation:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextEditor(text: Binding(
                    get: { coordinator.mathPreamble },
                    set: { coordinator.setMathPreamble($0) }
                ))
                .font(.system(size: 12.5, design: .monospaced))
                .frame(minHeight: 110)
                .padding(4)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )

                Text("Example: #let inner(x, y) = $lr(angle.l #x, #y angle.r)$  →  use $inner(a, b)$ in notes")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            Divider()

            Text("Config file: \(PersistenceManager.configFileURL.path)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
        .padding(20)
        .frame(width: 480)
    }
}
