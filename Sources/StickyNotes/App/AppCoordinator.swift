import AppKit
import SwiftUI
import Combine

/// Main coordinator that manages the application state and components
class AppCoordinator: ObservableObject {
    // MARK: - Published Properties

    @Published var noteManager: NoteManager
    @Published var windowManager: WindowManager
    @Published var mathRenderer: MathRenderer
    @Published var mathPreamble: String
    @Published private(set) var focusedOpacity: Double
    @Published private(set) var unfocusedOpacity: Double

    // MARK: - Properties

    /// Set to true during app termination to prevent note deletion on window close
    var isQuitting = false

    // MARK: - Private Properties

    private let persistenceManager: PersistenceManager
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?
    private var interactionTimer: Timer?
    private var optionClickMonitor: Any?

    // MARK: - Initialization

    init() {
        let pm = PersistenceManager()
        self.persistenceManager = pm
        self.noteManager = NoteManager(persistenceManager: pm)
        self.windowManager = WindowManager()
        let initialRenderer = pm.loadMathRenderer()
        let initialPreamble = pm.loadMathPreamble()
        self.mathRenderer = initialRenderer
        self.mathPreamble = initialPreamble
        self.focusedOpacity = pm.loadOpacity("focusedOpacity", default: 0.95)
        self.unfocusedOpacity = pm.loadOpacity("unfocusedOpacity", default: 0.55)

        // Wire up SharedWebViewManager
        SharedWebViewManager.shared.coordinator = self
        SharedWebViewManager.shared.setMathRenderer(initialRenderer)
        SharedWebViewManager.shared.setMathPreamble(initialPreamble)

        setupBindings()
        openInitialWindows()
        // Poll current modifier state without requiring global keyboard-monitor permissions.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            self?.refreshNoteInteraction()
        }
        RunLoop.main.add(timer, forMode: .common)
        interactionTimer = timer
        optionClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if let window = event.window,
               let id = self?.windowManager.noteId(for: window) {
                self?.windowManager.getWindowController(for: id)?.focus()
            }
            return event
        }
        for notification in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.publisher(for: notification)
                .sink { [weak self] _ in self?.refreshNoteInteraction() }
                .store(in: &cancellables)
        }
    }

    deinit {
        interactionTimer?.invalidate()
        if let monitor = optionClickMonitor { NSEvent.removeMonitor(monitor) }
    }

    func refreshNoteInteraction() {
        for id in windowManager.getAllWindowIds() {
            windowManager.getWindowController(for: id)?.refreshInteraction()
        }
    }

    func setFocusedOpacity(_ opacity: Double) {
        focusedOpacity = min(1, max(0.2, opacity))
        persistenceManager.saveOpacity(focusedOpacity, forKey: "focusedOpacity")
        for note in noteManager.notes {
            setNoteOpacity(noteId: note.id, opacity: focusedOpacity)
        }
    }

    func setUnfocusedOpacity(_ opacity: Double) {
        unfocusedOpacity = min(1, max(0.2, opacity))
        persistenceManager.saveOpacity(unfocusedOpacity, forKey: "unfocusedOpacity")
        refreshNoteInteraction()
    }

    // MARK: - Public Methods

    /// Create a new note and open its window on the current screen
    func createNewNote() {
        let position = calculateNewNotePosition()
        var note = noteManager.createNote(position: position)
        note.opacity = focusedOpacity
        noteManager.updateNoteWindow(note.id, opacity: focusedOpacity)
        windowManager.openWindow(for: note, coordinator: self)
    }

    /// Called when a note window is closing (from windowWillClose delegate).
    /// If the app is quitting, skip — saveAllNotesImmediately() handles bulk save.
    /// Otherwise, delete the note (Apple Stickies behavior).
    func closeNoteWindow(_ noteId: UUID) {
        windowManager.removeWindow(for: noteId)
        SharedWebViewManager.shared.removeCachedState(for: noteId)

        if isQuitting {
            return
        }
        // User explicitly closed — delete the note
        noteManager.deleteNote(noteId)
    }

    /// Handle note content changes from the editor
    func handleContentChange(noteId: UUID, content: String) {
        noteManager.updateNoteContent(noteId, content: content)
    }

    /// Handle window state changes
    func handleWindowStateChange(
        noteId: UUID,
        position: CGPoint? = nil,
        size: CGSize? = nil,
        isMinimized: Bool? = nil
    ) {
        noteManager.updateNoteWindow(
            noteId,
            position: position,
            size: size,
            isMinimized: isMinimized
        )
    }

    /// Reopen windows for all existing notes
    func showAllNotes() {
        for note in noteManager.notes {
            windowManager.openWindow(for: note, coordinator: self)
        }
    }

    /// Change a note's color theme
    func changeNoteColor(noteId: UUID, colorTheme: String) {
        noteManager.updateNoteColor(noteId, colorTheme: colorTheme)
        windowManager.getWindowController(for: noteId)?.setColorTheme(colorTheme)
    }

    /// Change a note's opacity
    func setNoteOpacity(noteId: UUID, opacity: Double) {
        noteManager.updateNoteWindow(noteId, opacity: opacity)
        windowManager.getWindowController(for: noteId)?.setOpacity(opacity)
    }

    /// Toggle a note's always-on-top setting
    func setNoteAlwaysOnTop(noteId: UUID, alwaysOnTop: Bool) {
        noteManager.updateNoteAlwaysOnTop(noteId, alwaysOnTop: alwaysOnTop)
        windowManager.getWindowController(for: noteId)?.setAlwaysOnTop(alwaysOnTop)
    }

    /// Change the math rendering engine (Typst or LaTeX)
    func setMathRenderer(_ renderer: MathRenderer) {
        guard mathRenderer != renderer else { return }
        mathRenderer = renderer
        persistenceManager.saveMathRenderer(renderer)
        SharedWebViewManager.shared.setMathRenderer(renderer)
    }

    /// Update the custom math preamble / overhead
    func setMathPreamble(_ preamble: String) {
        guard mathPreamble != preamble else { return }
        mathPreamble = preamble
        persistenceManager.saveMathPreamble(preamble)
        SharedWebViewManager.shared.setMathPreamble(preamble)
    }

    /// Open and focus the Settings window above floating note panels
    func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: SettingsView(coordinator: self))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "MD Sticky Notes Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()
        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Get the note ID of the currently focused window
    func focusedNoteId() -> UUID? {
        guard let keyWindow = NSApp.keyWindow else { return nil }
        return windowManager.noteId(for: keyWindow)
    }

    /// Cycle focus to the next note window (Cmd+`)
    func cycleToNextWindow() {
        let allIds = windowManager.getAllWindowIds()
            .sorted { $0.uuidString < $1.uuidString }
        guard !allIds.isEmpty else { return }

        if let currentId = focusedNoteId(),
           let idx = allIds.firstIndex(of: currentId) {
            let next = allIds[(idx + 1) % allIds.count]
            windowManager.bringToFront(next)
        } else {
            windowManager.bringToFront(allIds[0])
        }
    }

    // MARK: - Last Active Note Persistence

    private static let lastActiveNoteKey = "lastActiveNoteId"

    /// Save the currently focused note ID to UserDefaults
    func saveLastActiveNote() {
        if let noteId = focusedNoteId() {
            UserDefaults.standard.set(noteId.uuidString, forKey: Self.lastActiveNoteKey)
        }
    }

    /// Restore focus to the last active note (called after app launch)
    func restoreLastActiveNote() {
        guard let idString = UserDefaults.standard.string(forKey: Self.lastActiveNoteKey),
              let noteId = UUID(uuidString: idString) else { return }

        // Small delay to ensure windows are fully loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.windowManager.bringToFront(noteId)
        }
    }

    /// Flush JS editor content and cursor position, then save — called on app termination
    func saveAllNotesImmediately() {
        // Flush the single shared WKWebView's current state
        SharedWebViewManager.shared.flushCurrentNoteState()

        // Filter out empty notes, then save to disk
        let nonEmptyNotes = noteManager.notes.filter {
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        persistenceManager.saveNotes(nonEmptyNotes)
    }

    // MARK: - Private Methods

    private func setupBindings() {
        noteManager.$notes
            .sink { [weak self] notes in
                self?.syncWindowsWithNotes(notes)
            }
            .store(in: &cancellables)
    }

    /// Open windows for all persisted notes
    private func openInitialWindows() {
        for note in noteManager.notes {
            windowManager.openWindow(for: note, coordinator: self)
        }
    }

    /// Calculate position for a new note: mouse cursor's screen, cascade from center
    private func calculateNewNotePosition() -> CGPoint {
        let noteSize = CGSize(width: 300, height: 360)

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame

        let existingFrames: [NSRect] = windowManager.getAllWindowIds().compactMap {
            windowManager.getWindowController(for: $0)?.window?.frame
        }
        let count = existingFrames.filter { visibleFrame.intersects($0) }.count

        let step: CGFloat = 30
        let x = visibleFrame.midX - noteSize.width / 2 + CGFloat(count) * step
        let y = visibleFrame.midY - noteSize.height / 2 - CGFloat(count) * step

        return CGPoint(
            x: min(max(x, visibleFrame.minX), visibleFrame.maxX - noteSize.width),
            y: min(max(y, visibleFrame.minY), visibleFrame.maxY - noteSize.height)
        )
    }

    private func syncWindowsWithNotes(_ notes: [Note]) {
        let noteIds = Set(notes.map { $0.id })
        let windowIds = Set(windowManager.getAllWindowIds())

        let windowsToClose = windowIds.subtracting(noteIds)
        for windowId in windowsToClose {
            windowManager.closeWindow(for: windowId)
        }
    }
}
