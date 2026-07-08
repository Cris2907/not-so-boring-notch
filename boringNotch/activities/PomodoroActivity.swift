import Combine
import SwiftUI

extension ActivityID {
    static let pomodoro = ActivityID("builtin.pomodoro")
}

@MainActor
final class PomodoroActivity: NotchActivity {
    static let activityID = ActivityID.pomodoro

    let id = activityID
    let metadata = ActivityMetadata(
        name: String(localized: "Pomodoro"),
        systemImage: "timer",
        tint: .red,
        summary: String(localized: "Run focused work sessions and timed breaks.")
    )

    private let manager: PomodoroManager
    private var managerObservation: AnyCancellable?

    init(manager: PomodoroManager? = nil) {
        self.manager = manager ?? .shared
        managerObservation = self.manager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var isActive: Bool { manager.isActive }
    var supportsCompactPresentation: Bool { true }
    var livePresentationState: ActivityLivePresentationState {
        switch manager.snapshot?.phase {
        case .running:
            return .visible(priority: .normal)
        case .paused:
            return .visible(priority: .low)
        case .ready, nil:
            return .hidden
        }
    }
    let livePresentationSizing = LiveActivityPresentationSizing(
        minimalContentWidth: .fixed(0)
    )
    var supportsConfiguration: Bool { true }

    func makeExpandedView() -> some View {
        PomodoroActivityView(manager: manager)
    }

    func makeCompactView() -> some View {
        PomodoroCompactView(manager: manager)
    }

    func makeLivePresentationView() -> some View {
        PomodoroLivePresentationView(manager: manager)
    }

    func makeMinimalLivePresentationView() -> some View {
        EmptyView()
    }

    func makeConfigurationView() -> some View {
        PomodoroSettingsView()
    }
}
