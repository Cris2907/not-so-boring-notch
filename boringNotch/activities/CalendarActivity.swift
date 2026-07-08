import Combine
import Defaults
import SwiftUI

extension ActivityID {
    static let calendar = ActivityID("calendar")
}

@MainActor
final class CalendarActivity: NotchActivity {
    static let activityID = ActivityID.calendar

    let id = activityID
    let metadata = ActivityMetadata(
        name: String(localized: "Calendar"),
        systemImage: "calendar",
        tint: .red,
        preferredExpandedHeight: calendarOpenNotchHeight,
        summary: String(localized: "View upcoming events and reminders.")
    )

    @Published private(set) var isAvailable: Bool

    private var availabilityObservation: AnyCancellable?

    init() {
        isAvailable = Defaults[.showCalendar]
        availabilityObservation = Defaults.publisher(.showCalendar)
            .map(\.newValue)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isAvailable in
                self?.isAvailable = isAvailable
            }
    }

    var supportsConfiguration: Bool { true }

    func makeExpandedView() -> some View {
        CalendarView()
    }

    func makeConfigurationView() -> some View {
        CalendarSettings()
    }
}
