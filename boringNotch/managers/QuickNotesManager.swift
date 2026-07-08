import Foundation

@MainActor
final class QuickNotesManager: ObservableObject {
    static let shared = QuickNotesManager()
    static let maximumCharacterCount = 262

    @Published private(set) var note: String

    var hasMeaningfulContent: Bool {
        !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let defaults: UserDefaults
    private let persistenceKey: String

    init(
        defaults: UserDefaults = .standard,
        persistenceKey: String = "quickNotes.note"
    ) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        let persistedNote = defaults.string(forKey: persistenceKey) ?? ""
        note = Self.limitedNote(persistedNote)

        if note != persistedNote {
            defaults.set(note, forKey: persistenceKey)
        }
    }

    func updateNote(_ newValue: String) {
        let limitedValue = Self.limitedNote(newValue)
        guard note != limitedValue else { return }

        note = limitedValue
        if limitedValue.isEmpty {
            defaults.removeObject(forKey: persistenceKey)
        } else {
            defaults.set(limitedValue, forKey: persistenceKey)
        }
    }

    func clear() {
        updateNote("")
    }

    func singleLinePreview(characterLimit: Int = 48) -> String {
        let normalized = note
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        guard characterLimit > 0 else { return "" }
        guard normalized.count > characterLimit else { return normalized }
        guard characterLimit > 1 else { return "…" }
        return String(normalized.prefix(characterLimit - 1)) + "…"
    }

    private static func limitedNote(_ note: String) -> String {
        String(note.prefix(maximumCharacterCount))
    }
}
