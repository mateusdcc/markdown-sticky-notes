import Foundation
import Combine

/// Manages persistence of notes using UserDefaults
class PersistenceManager: ObservableObject {
    // MARK: - Properties

    private let userDefaults: UserDefaults
    private let notesKey = "sticky_notes"
    private let mathRendererKey = "mathRenderer"
    private let mathPreambleKey = "mathPreamble"
    static let defaultMathPreamble = "#let inner(x, y) = $lr(angle.l #x, #y angle.r)$"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Debounce timer for auto-save
    private var saveTimer: Timer?
    private let saveDelay: TimeInterval = 0.5 // 500ms debounce

    // MARK: - Initialization

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        // Configure JSON encoder/decoder
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Public Methods

    /// Load all notes from persistent storage
    /// - Returns: Array of Note objects, or empty array if none exist or on error
    func loadNotes() -> [Note] {
        guard let data = userDefaults.data(forKey: notesKey) else {
            print("[PersistenceManager] No saved notes found")
            return []
        }

        do {
            let notes = try decoder.decode([Note].self, from: data)
            print("[PersistenceManager] Loaded \(notes.count) notes")
            return notes
        } catch {
            print("[PersistenceManager] Error loading notes: \(error)")
            // If there's corrupted data, backup and reset
            backupCorruptedData(data)
            return []
        }
    }

    /// Save all notes to persistent storage
    /// - Parameter notes: Array of notes to save
    func saveNotes(_ notes: [Note]) {
        do {
            let data = try encoder.encode(notes)
            userDefaults.set(data, forKey: notesKey)
            print("[PersistenceManager] Saved \(notes.count) notes")
        } catch {
            print("[PersistenceManager] Error saving notes: \(error)")
        }
    }

    /// Save notes with debouncing to reduce I/O operations
    /// - Parameter notes: Array of notes to save
    func saveNotesDebounced(_ notes: [Note]) {
        // Invalidate existing timer
        saveTimer?.invalidate()

        // Create new timer
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDelay, repeats: false) { [weak self] _ in
            self?.saveNotes(notes)
        }
    }

    /// Save a single note immediately (for critical operations like window close)
    /// - Parameters:
    ///   - note: The note to save
    ///   - notes: Current array of all notes
    func saveNoteImmediately(_ note: Note, in notes: inout [Note]) {
        // Find and update the note in the array
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        } else {
            notes.append(note)
        }

        saveNotes(notes)
    }

    /// Delete a note from persistent storage
    /// - Parameters:
    ///   - note: The note to delete
    ///   - notes: Current array of all notes
    func deleteNote(_ note: Note, from notes: inout [Note]) {
        notes.removeAll { $0.id == note.id }
        saveNotes(notes)
    }

    /// Clear all notes (useful for testing or reset)
    func clearAllNotes() {
        userDefaults.removeObject(forKey: notesKey)
        print("[PersistenceManager] Cleared all notes")
    }

    func loadOpacity(_ key: String, default defaultValue: Double) -> Double {
        guard let value = userDefaults.object(forKey: key) as? Double,
              value.isFinite else { return defaultValue }
        return min(1, max(0.2, value))
    }

    func saveOpacity(_ value: Double, forKey key: String) {
        userDefaults.set(min(1, max(0.2, value)), forKey: key)
    }

    // MARK: - App Configuration (Math Renderer)

    /// Primary config file URL (~/.config/md-sticky-notes/config.json)
    static var configFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/md-sticky-notes/config.json")
    }

    /// Alternate config file URL (~/.config/markdown-sticky-notes/config.json)
    private static var alternateConfigFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/markdown-sticky-notes/config.json")
    }

    /// Load the configured math renderer from config file or UserDefaults (defaults to .typst)
    func loadMathRenderer() -> MathRenderer {
        for url in [Self.configFileURL, Self.alternateConfigFileURL] {
            if let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let raw = (json["mathRenderer"] as? String) ?? (json["math_renderer"] as? String) {
                let renderer = MathRenderer.from(raw)
                userDefaults.set(renderer.rawValue, forKey: mathRendererKey)
                print("[PersistenceManager] Loaded mathRenderer '\(renderer.rawValue)' from \(url.path)")
                return renderer
            }
        }

        if let saved = userDefaults.string(forKey: mathRendererKey) {
            let renderer = MathRenderer.from(saved)
            saveMathRenderer(renderer)
            return renderer
        }

        let defaultRenderer: MathRenderer = .typst
        saveMathRenderer(defaultRenderer)
        return defaultRenderer
    }

    /// Save the math renderer setting to both UserDefaults and ~/.config/md-sticky-notes/config.json
    func saveMathRenderer(_ renderer: MathRenderer) {
        userDefaults.set(renderer.rawValue, forKey: mathRendererKey)

        let url = Self.configFileURL
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var configObj: [String: Any] = [:]
            if let existingData = try? Data(contentsOf: url),
               let existing = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
                configObj = existing
            }
            configObj["mathRenderer"] = renderer.rawValue
            let data = try JSONSerialization.data(withJSONObject: configObj, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            print("[PersistenceManager] Saved mathRenderer '\(renderer.rawValue)' to \(url.path)")
        } catch {
            print("[PersistenceManager] Error saving config file: \(error)")
        }
    }

    /// Load the custom math preamble/overhead from config file or UserDefaults
    func loadMathPreamble() -> String {
        for url in [Self.configFileURL, Self.alternateConfigFileURL] {
            if let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let raw = (json["mathPreamble"] as? String)
                   ?? (json["customOverhead"] as? String)
                   ?? (json["preamble"] as? String) {
                userDefaults.set(raw, forKey: mathPreambleKey)
                print("[PersistenceManager] Loaded mathPreamble from \(url.path)")
                return raw
            }
        }

        if let saved = userDefaults.string(forKey: mathPreambleKey) {
            saveMathPreamble(saved)
            return saved
        }

        let defaultPreamble = Self.defaultMathPreamble
        saveMathPreamble(defaultPreamble)
        return defaultPreamble
    }

    /// Save the custom math preamble/overhead to both UserDefaults and ~/.config/md-sticky-notes/config.json
    func saveMathPreamble(_ preamble: String) {
        userDefaults.set(preamble, forKey: mathPreambleKey)

        let url = Self.configFileURL
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var configObj: [String: Any] = [:]
            if let existingData = try? Data(contentsOf: url),
               let existing = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
                configObj = existing
            }
            configObj["mathPreamble"] = preamble
            let data = try JSONSerialization.data(withJSONObject: configObj, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            print("[PersistenceManager] Saved mathPreamble to \(url.path)")
        } catch {
            print("[PersistenceManager] Error saving mathPreamble to config file: \(error)")
        }
    }

    // MARK: - Private Methods

    /// Backup corrupted data for debugging
    /// - Parameter data: The corrupted data
    private func backupCorruptedData(_ data: Data) {
        let backupKey = "sticky_notes_corrupted_backup_\(Date().timeIntervalSince1970)"
        userDefaults.set(data, forKey: backupKey)
        print("[PersistenceManager] Backed up corrupted data to key: \(backupKey)")
    }

    /// Export notes to a file (for future functionality)
    /// - Parameters:
    ///   - notes: Notes to export
    ///   - url: URL to save to
    func exportNotes(_ notes: [Note], to url: URL) throws {
        let data = try encoder.encode(notes)
        try data.write(to: url)
        print("[PersistenceManager] Exported \(notes.count) notes to \(url.path)")
    }

    /// Import notes from a file (for future functionality)
    /// - Parameter url: URL to import from
    /// - Returns: Imported notes
    func importNotes(from url: URL) throws -> [Note] {
        let data = try Data(contentsOf: url)
        let notes = try decoder.decode([Note].self, from: data)
        print("[PersistenceManager] Imported \(notes.count) notes from \(url.path)")
        return notes
    }
}
