import Foundation

@MainActor
final class QuickNotesManager: ObservableObject {
    static let shared = QuickNotesManager()

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
        note = defaults.string(forKey: persistenceKey) ?? ""
    }

    func updateNote(_ newValue: String) {
        guard note != newValue else { return }

        note = newValue
        if newValue.isEmpty {
            defaults.removeObject(forKey: persistenceKey)
        } else {
            defaults.set(newValue, forKey: persistenceKey)
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
}
