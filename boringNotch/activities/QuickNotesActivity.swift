import Combine
import SwiftUI

extension ActivityID {
    static let quickNotes = ActivityID("builtin.quick-notes")
}

@MainActor
final class QuickNotesActivity: NotchActivity {
    static let activityID = ActivityID.quickNotes

    let id = activityID
    let metadata = ActivityMetadata(
        name: String(localized: "Quick Notes"),
        systemImage: "note.text",
        tint: .orange,
        summary: String(localized: "Keep a short note close at hand.")
    )

    private let manager: QuickNotesManager
    private var managerObservation: AnyCancellable?

    init(manager: QuickNotesManager? = nil) {
        self.manager = manager ?? .shared
        managerObservation = self.manager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var isActive: Bool { manager.hasMeaningfulContent }

    var livePresentationState: ActivityLivePresentationState {
        manager.hasMeaningfulContent ? .visible(priority: .normal) : .hidden
    }

    let livePresentationSizing = LiveActivityPresentationSizing(
        fullContentWidth: .fixed(140),
        minimalContentWidth: .fixed(42)
    )

    var supportsConfiguration: Bool { true }

    func makeExpandedView() -> some View {
        QuickNotesActivityView(manager: manager)
    }

    func makeLivePresentationView() -> some View {
        QuickNotesLivePresentationView(manager: manager)
    }

    func makeMinimalLivePresentationView() -> some View {
        QuickNotesMinimalLivePresentationView(manager: manager)
    }

    func makeConfigurationView() -> some View {
        QuickNotesSettingsView()
    }
}
