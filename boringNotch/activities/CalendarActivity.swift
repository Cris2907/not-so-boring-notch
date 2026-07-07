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
        name: "Calendar",
        systemImage: "calendar",
        tint: .red,
        preferredExpandedHeight: calendarOpenNotchHeight
    )

    @Published private(set) var isAvailable: Bool

    private let manager: CalendarManager
    private let now: () -> Date
    private var availabilityObservation: AnyCancellable?
    private var managerObservation: AnyCancellable?
    private var boundaryTask: Task<Void, Never>?
    private let schedulesBoundaryUpdates: Bool

    init(
        manager: CalendarManager? = nil,
        now: @escaping () -> Date = Date.init,
        schedulesBoundaryUpdates: Bool = true
    ) {
        self.manager = manager ?? .shared
        self.now = now
        self.schedulesBoundaryUpdates = schedulesBoundaryUpdates
        isAvailable = Defaults[.showCalendar]
        availabilityObservation = Defaults.publisher(.showCalendar)
            .map(\.newValue)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isAvailable in
                self?.isAvailable = isAvailable
            }

        managerObservation = self.manager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
            self?.scheduleBoundaryRefreshAfterManagerChange()
        }

        scheduleNextBoundaryRefresh()
    }

    deinit {
        boundaryTask?.cancel()
    }

    var livePresentationState: ActivityLivePresentationState {
        liveEvent == nil ? .hidden : .visible(priority: .normal)
    }
    var supportsConfiguration: Bool { true }

    func makeExpandedView() -> some View {
        CalendarView()
    }

    func makeLivePresentationView() -> some View {
        CalendarLivePresentationView(manager: manager, now: now)
    }

    func makeMinimalLivePresentationView() -> some View {
        CalendarMinimalLivePresentationView(manager: manager, now: now)
    }

    func makeConfigurationView() -> some View {
        CalendarSettings()
    }

    private var liveEvent: EventModel? {
        CalendarLiveEventSelector.select(from: manager.events, at: now())
    }

    private func scheduleBoundaryRefreshAfterManagerChange() {
        guard schedulesBoundaryUpdates else { return }

        Task { @MainActor [weak self] in
            await Task.yield()
            self?.scheduleNextBoundaryRefresh()
        }
    }

    private func scheduleNextBoundaryRefresh() {
        boundaryTask?.cancel()
        guard schedulesBoundaryUpdates,
              let boundary = CalendarLiveEventSelector.nextBoundary(
                in: manager.events,
                after: now()
              )
        else { return }

        let delay = max(0, boundary.timeIntervalSince(now()))
        boundaryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }

            guard !Task.isCancelled, let self else { return }
            objectWillChange.send()
            scheduleNextBoundaryRefresh()
        }
    }
}

enum CalendarLiveEventSelector {
    static func select(from events: [EventModel], at date: Date) -> EventModel? {
        eligibleEvents(from: events)
            .filter { $0.start <= date && date < $0.end }
            .sorted(by: eventOrder)
            .first
    }

    static func nextBoundary(in events: [EventModel], after date: Date) -> Date? {
        eligibleEvents(from: events)
            .flatMap { [$0.start, $0.end] }
            .filter { $0 > date }
            .min()
    }

    private static func eligibleEvents(from events: [EventModel]) -> [EventModel] {
        events.filter { event in
            !event.type.isReminder && !event.isAllDay && event.end > event.start
        }
    }

    private static func eventOrder(_ lhs: EventModel, _ rhs: EventModel) -> Bool {
        if lhs.start != rhs.start {
            return lhs.start > rhs.start
        }
        if lhs.end != rhs.end {
            return lhs.end < rhs.end
        }
        return lhs.id < rhs.id
    }
}
