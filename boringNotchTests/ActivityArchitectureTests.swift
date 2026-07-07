import Combine
import Defaults
import SwiftUI
import XCTest
@testable import boringNotch

@MainActor
final class ActivityArchitectureTests: XCTestCase {
    func testActivityIDHasStableValueSemantics() {
        let first = ActivityID("example")
        let second = ActivityID(rawValue: "example")

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.rawValue, "example")
        XCTAssertEqual(first.description, "example")
        XCTAssertEqual(Set([first, second]).count, 1)
    }

    func testRegistryPreservesRegistrationOrderAndMetadata() throws {
        let first = TestActivity(id: "first", name: "First")
        let second = TestActivity(id: "second", name: "Second")
        let registry = try ActivityRegistry {
            first
            second
        }

        XCTAssertEqual(registry.activities.map(\.id), [first.id, second.id])
        XCTAssertEqual(registry.activity(for: second.id)?.metadata.name, "Second")
        XCTAssertNil(registry.activity(for: ActivityID("missing")))
    }

    func testRegistryRejectsDuplicateIDs() {
        XCTAssertThrowsError(
            try ActivityRegistry {
                TestActivity(id: "duplicate", name: "First")
                TestActivity(id: "duplicate", name: "Second")
            }
        ) { error in
            XCTAssertEqual(
                error as? ActivityRegistryError,
                .duplicateID(ActivityID("duplicate"))
            )
        }
    }

    func testAvailabilityAndActiveStateAreEvaluatedFromActivity() throws {
        let activity = TestActivity(id: "state", name: "State")
        let registry = try ActivityRegistry { activity }

        XCTAssertEqual(registry.availableActivities.map(\.id), [activity.id])
        XCTAssertTrue(registry.activeActivities.isEmpty)

        activity.isAvailable = false
        activity.isActive = true
        XCTAssertTrue(registry.availableActivities.isEmpty)
        XCTAssertTrue(registry.activeActivities.isEmpty)

        activity.isAvailable = true
        XCTAssertEqual(registry.activeActivities.map(\.id), [activity.id])
    }

    func testStateChangesPropagateThroughTypeErasureAndRegistry() throws {
        let activity = TestActivity(id: "observable", name: "Observable")
        let registry = try ActivityRegistry { activity }
        let erased = try XCTUnwrap(registry.activity(for: activity.id))
        var erasedUpdates = 0
        var registryUpdates = 0
        let erasedObservation = erased.objectWillChange.sink { erasedUpdates += 1 }
        let registryObservation = registry.objectWillChange.sink { registryUpdates += 1 }

        activity.isActive = true

        XCTAssertEqual(erasedUpdates, 1)
        XCTAssertEqual(registryUpdates, 1)
        withExtendedLifetime((erasedObservation, registryObservation)) {}
    }

    func testExampleActivityUsesConcreteViewsBeforeErasure() throws {
        let example = ExampleActivity()
        let registry = try ActivityRegistry { example }
        let erased = try XCTUnwrap(registry.activity(for: ExampleActivity.activityID))

        let _: AnyView = erased.makeExpandedView()
        let _: AnyView = erased.makeCompactView()
        let _: AnyView = erased.makeLivePresentationView()
        let _: AnyView = erased.makeMinimalLivePresentationView()
        XCTAssertTrue(erased.supportsCompactPresentation)
        XCTAssertEqual(erased.livePresentationState, .hidden)
        XCTAssertFalse(erased.supportsConfiguration)
        XCTAssertFalse(ActivityRegistry.shared.activities.contains { $0.id == example.id })
    }

    func testLiveSelectionRequiresExplicitVisibilityAndAvailability() throws {
        let activeButHidden = LiveTestActivity(
            id: "active-hidden",
            state: .hidden,
            isActive: true
        )
        let unavailable = LiveTestActivity(
            id: "unavailable",
            state: .visible(priority: .high),
            isAvailable: false
        )
        let eligible = LiveTestActivity(
            id: "eligible",
            state: .visible(priority: .low)
        )
        let registry = try ActivityRegistry {
            activeButHidden
            unavailable
            eligible
        }

        assertStack(
            selectedActivityLivePresentationStack(from: registry.activities, snapshot: .empty),
            contains: [eligible.id]
        )
    }

    func testSingleEligibleLiveSelectionUsesFullPresentation() throws {
        let activity = LiveTestActivity(id: "single", state: .visible(priority: .normal))
        let registry = try ActivityRegistry { activity }

        switch selectedActivityLivePresentationStack(from: registry.activities, snapshot: .empty) {
        case .full(let selected):
            XCTAssertEqual(selected.id, activity.id)
        default:
            XCTFail("Expected a single eligible activity to use the full live presentation")
        }
    }

    func testLiveSelectionUsesRecencyInsteadOfPriority() throws {
        let high = LiveTestActivity(id: "high", state: .visible(priority: .high))
        let low = LiveTestActivity(id: "low", state: .visible(priority: .low))
        let registry = try ActivityRegistry {
            high
            low
        }
        let snapshot = ActivityLivePresentationSnapshot(startedSequences: [
            high.id: 1,
            low.id: 2
        ])

        assertStack(
            selectedActivityLivePresentationStack(from: registry.activities, snapshot: snapshot),
            contains: [high.id, low.id]
        )
    }

    func testTwoEligibleLiveActivitiesUseMinimalSplitWithNewestTrailing() throws {
        let first = LiveTestActivity(id: "first", state: .visible(priority: .normal))
        let second = LiveTestActivity(id: "second", state: .visible(priority: .normal))
        let registry = try ActivityRegistry {
            first
            second
        }
        let snapshot = ActivityLivePresentationSnapshot(startedSequences: [
            first.id: 1,
            second.id: 2
        ])

        switch selectedActivityLivePresentationStack(from: registry.activities, snapshot: snapshot) {
        case .split(let leading, let trailing):
            XCTAssertEqual(leading.id, first.id)
            XCTAssertEqual(trailing.id, second.id)
        default:
            XCTFail("Expected two eligible activities to use split minimal live presentations")
        }
    }

    func testMoreThanTwoLiveActivitiesUseTwoMostRecent() throws {
        let oldest = LiveTestActivity(id: "oldest", state: .visible(priority: .normal))
        let newest = LiveTestActivity(id: "newest", state: .visible(priority: .normal))
        let middle = LiveTestActivity(id: "middle", state: .visible(priority: .normal))
        let registry = try ActivityRegistry {
            oldest
            newest
            middle
        }
        let snapshot = ActivityLivePresentationSnapshot(startedSequences: [
            oldest.id: 1,
            newest.id: 3,
            middle.id: 2
        ])

        assertStack(
            selectedActivityLivePresentationStack(from: registry.activities, snapshot: snapshot),
            contains: [middle.id, newest.id]
        )
    }

    func testMissingRecencyFallsBackToRegistrationOrderDeterministically() throws {
        let first = LiveTestActivity(id: "first", state: .visible(priority: .normal))
        let second = LiveTestActivity(id: "second", state: .visible(priority: .normal))
        let registry = try ActivityRegistry {
            first
            second
        }

        assertStack(
            selectedActivityLivePresentationStack(from: registry.activities, snapshot: .empty),
            contains: [second.id, first.id]
        )
    }

    func testLiveStateChangesPropagateThroughErasureWithoutRegistryState() throws {
        let activity = LiveTestActivity(id: "live", state: .hidden)
        let registry = try ActivityRegistry { activity }
        let erased = try XCTUnwrap(registry.activity(for: activity.id))
        var registryUpdates = 0
        let observation = registry.objectWillChange.sink { registryUpdates += 1 }

        assertStack(
            selectedActivityLivePresentationStack(from: registry.activities, snapshot: .empty),
            contains: []
        )
        let _: AnyView = erased.makeLivePresentationView()
        let _: AnyView = erased.makeMinimalLivePresentationView()

        activity.livePresentationState = .visible(priority: .normal)

        assertStack(
            selectedActivityLivePresentationStack(from: registry.activities, snapshot: .empty),
            contains: [activity.id]
        )
        XCTAssertEqual(registryUpdates, 1)
        withExtendedLifetime(observation) {}
    }

    func testCoordinatorAssignsRecencyWhenActivityBecomesEligible() async throws {
        let first = LiveTestActivity(id: "first", state: .hidden)
        let second = LiveTestActivity(id: "second", state: .hidden)
        let registry = try ActivityRegistry {
            first
            second
        }
        let coordinator = ActivityLivePresentationCoordinator(registry: registry)

        first.livePresentationState = .visible(priority: .normal)
        await coordinator.waitForPendingReconciliation()

        second.livePresentationState = .visible(priority: .normal)
        await coordinator.waitForPendingReconciliation()

        XCTAssertLessThan(
            try XCTUnwrap(coordinator.snapshot.startedSequence(for: first.id)),
            try XCTUnwrap(coordinator.snapshot.startedSequence(for: second.id))
        )
        assertStack(
            selectedActivityLivePresentationStack(
                from: registry.activities,
                snapshot: coordinator.snapshot
            ),
            contains: [first.id, second.id]
        )
    }

    func testCoordinatorDoesNotRefreshRecencyForVisibleStateChanges() async throws {
        let first = LiveTestActivity(id: "first", state: .hidden)
        let second = LiveTestActivity(id: "second", state: .hidden)
        let registry = try ActivityRegistry {
            first
            second
        }
        let coordinator = ActivityLivePresentationCoordinator(registry: registry)

        first.livePresentationState = .visible(priority: .low)
        await coordinator.waitForPendingReconciliation()
        let originalSequence = try XCTUnwrap(coordinator.snapshot.startedSequence(for: first.id))

        first.livePresentationState = .visible(priority: .high)
        await coordinator.waitForPendingReconciliation()

        XCTAssertEqual(coordinator.snapshot.startedSequence(for: first.id), originalSequence)

        second.livePresentationState = .visible(priority: .normal)
        await coordinator.waitForPendingReconciliation()

        assertStack(
            selectedActivityLivePresentationStack(
                from: registry.activities,
                snapshot: coordinator.snapshot
            ),
            contains: [first.id, second.id]
        )
    }

    func testCoordinatorRemovesHiddenActivityAndPromotesNextMostRecent() async throws {
        let first = LiveTestActivity(id: "first", state: .hidden)
        let second = LiveTestActivity(id: "second", state: .hidden)
        let third = LiveTestActivity(id: "third", state: .hidden)
        let registry = try ActivityRegistry {
            first
            second
            third
        }
        let coordinator = ActivityLivePresentationCoordinator(registry: registry)

        first.livePresentationState = .visible(priority: .normal)
        await coordinator.waitForPendingReconciliation()
        second.livePresentationState = .visible(priority: .normal)
        await coordinator.waitForPendingReconciliation()
        third.livePresentationState = .visible(priority: .normal)
        await coordinator.waitForPendingReconciliation()

        assertStack(
            selectedActivityLivePresentationStack(
                from: registry.activities,
                snapshot: coordinator.snapshot
            ),
            contains: [second.id, third.id]
        )

        third.livePresentationState = .hidden
        await coordinator.waitForPendingReconciliation()

        assertStack(
            selectedActivityLivePresentationStack(
                from: registry.activities,
                snapshot: coordinator.snapshot
            ),
            contains: [first.id, second.id]
        )
        XCTAssertNil(coordinator.snapshot.startedSequence(for: third.id))
    }

    func testCoordinatorRemovesUnavailableActivityAndRestartsWhenAvailableAgain() async throws {
        let first = LiveTestActivity(id: "first", state: .hidden)
        let second = LiveTestActivity(id: "second", state: .hidden)
        let registry = try ActivityRegistry {
            first
            second
        }
        let coordinator = ActivityLivePresentationCoordinator(registry: registry)

        first.livePresentationState = .visible(priority: .normal)
        await coordinator.waitForPendingReconciliation()
        second.livePresentationState = .visible(priority: .normal)
        await coordinator.waitForPendingReconciliation()

        second.isAvailable = false
        await coordinator.waitForPendingReconciliation()

        assertStack(
            selectedActivityLivePresentationStack(
                from: registry.activities,
                snapshot: coordinator.snapshot
            ),
            contains: [first.id]
        )
        XCTAssertNil(coordinator.snapshot.startedSequence(for: second.id))

        second.isAvailable = true
        await coordinator.waitForPendingReconciliation()

        assertStack(
            selectedActivityLivePresentationStack(
                from: registry.activities,
                snapshot: coordinator.snapshot
            ),
            contains: [first.id, second.id]
        )
    }

    func testCoordinatorUsesRegistryOrderForActivitiesEligibleAtLaunch() throws {
        let first = LiveTestActivity(id: "first", state: .visible(priority: .normal))
        let second = LiveTestActivity(id: "second", state: .visible(priority: .normal))
        let registry = try ActivityRegistry {
            first
            second
        }
        let coordinator = ActivityLivePresentationCoordinator(registry: registry)

        XCTAssertTrue(coordinator.snapshot.startedSequences.isEmpty)
        assertStack(
            selectedActivityLivePresentationStack(
                from: registry.activities,
                snapshot: coordinator.snapshot
            ),
            contains: [second.id, first.id]
        )
    }

    func testDefaultRegistryContainsCalendarMetadataAndConfiguration() throws {
        let calendar = try XCTUnwrap(ActivityRegistry.shared.activity(for: .calendar))

        XCTAssertEqual(calendar.metadata.name, "Calendar")
        XCTAssertEqual(calendar.metadata.systemImage, "calendar")
        XCTAssertEqual(calendar.metadata.preferredExpandedHeight, calendarOpenNotchHeight)
        XCTAssertTrue(calendar.supportsConfiguration)
        XCTAssertFalse(calendar.supportsCompactPresentation)
    }

    func testCalendarLiveEligibilityRequiresAnInProgressTimedEvent() {
        let now = Date(timeIntervalSince1970: 10_000)
        let manager = CalendarManager(
            currentDate: now,
            observesEventStoreChanges: false,
            loadsInitialData: false
        )
        let activity = CalendarActivity(
            manager: manager,
            now: { now },
            schedulesBoundaryUpdates: false
        )

        manager.events = [makeCalendarEvent(start: now.addingTimeInterval(60), end: now.addingTimeInterval(120))]
        XCTAssertEqual(activity.livePresentationState, .hidden)

        manager.events = [makeCalendarEvent(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(60), isAllDay: true)]
        XCTAssertEqual(activity.livePresentationState, .hidden)

        manager.events = [makeCalendarEvent(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(60), type: .reminder(completed: false))]
        XCTAssertEqual(activity.livePresentationState, .hidden)

        manager.events = [makeCalendarEvent(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(60))]
        XCTAssertEqual(activity.livePresentationState, .visible(priority: .normal))
        let _: AnyView = AnyView(activity.makeLivePresentationView())
        let _: AnyView = AnyView(activity.makeMinimalLivePresentationView())

        manager.events = [makeCalendarEvent(start: now.addingTimeInterval(-120), end: now)]
        XCTAssertEqual(activity.livePresentationState, .hidden)
    }

    func testCalendarLiveSelectorUsesCurrentEventAndExactNextBoundary() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let current = makeCalendarEvent(
            id: "current",
            start: now.addingTimeInterval(-30),
            end: now.addingTimeInterval(30)
        )
        let newerOverlap = makeCalendarEvent(
            id: "newer-overlap",
            start: now.addingTimeInterval(-10),
            end: now.addingTimeInterval(20)
        )
        let upcoming = makeCalendarEvent(
            id: "upcoming",
            start: now.addingTimeInterval(10),
            end: now.addingTimeInterval(40)
        )

        XCTAssertEqual(
            CalendarLiveEventSelector.select(from: [current, newerOverlap, upcoming], at: now)?.id,
            newerOverlap.id
        )
        XCTAssertEqual(
            try XCTUnwrap(
                CalendarLiveEventSelector.nextBoundary(
                    in: [current, newerOverlap, upcoming],
                    after: now
                )
            ),
            upcoming.start
        )
    }

    func testProductionPomodoroAndCalendarShareLivePresentationStack() async throws {
        let originalShowCalendar = Defaults[.showCalendar]
        Defaults[.showCalendar] = true
        defer { Defaults[.showCalendar] = originalShowCalendar }

        let now = Date(timeIntervalSince1970: 10_000)
        let calendarManager = CalendarManager(
            currentDate: now,
            observesEventStoreChanges: false,
            loadsInitialData: false
        )
        let calendar = CalendarActivity(
            manager: calendarManager,
            now: { now },
            schedulesBoundaryUpdates: false
        )
        let suiteName = "ActivityArchitectureTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let pomodoroManager = PomodoroManager(
            defaults: defaults,
            now: { now },
            configuration: { .standard },
            managesBackgroundExecution: false
        )
        let registry = try ActivityRegistry {
            calendar
            PomodoroActivity(manager: pomodoroManager)
        }
        let coordinator = ActivityLivePresentationCoordinator(registry: registry)

        XCTAssertEqual(registry.availableActivityIDs, [.calendar, .pomodoro])

        calendarManager.events = [
            makeCalendarEvent(
                start: now.addingTimeInterval(-60),
                end: now.addingTimeInterval(60)
            )
        ]
        await coordinator.waitForPendingReconciliation()
        assertStack(
            selectedActivityLivePresentationStack(
                from: registry.activities,
                snapshot: coordinator.snapshot
            ),
            contains: [.calendar]
        )

        pomodoroManager.start()
        await coordinator.waitForPendingReconciliation()
        let sharedStack = selectedActivityLivePresentationStack(
            from: registry.activities,
            snapshot: coordinator.snapshot
        )
        assertStack(
            sharedStack,
            contains: [.calendar, .pomodoro]
        )
        XCTAssertEqual(
            sharedStack.debugSelectionDescription,
            ".split(calendar, builtin.pomodoro)"
        )
        XCTAssertLessThan(
            try XCTUnwrap(coordinator.snapshot.startedSequence(for: .calendar)),
            try XCTUnwrap(coordinator.snapshot.startedSequence(for: .pomodoro))
        )

        calendarManager.events = []
        await coordinator.waitForPendingReconciliation()
        assertStack(
            selectedActivityLivePresentationStack(
                from: registry.activities,
                snapshot: coordinator.snapshot
            ),
            contains: [.pomodoro]
        )
        XCTAssertNil(coordinator.snapshot.startedSequence(for: .calendar))
        XCTAssertEqual(registry.availableActivityIDs, [.calendar, .pomodoro])
    }
}

private func makeCalendarEvent(
    id: String = "event",
    start: Date,
    end: Date,
    isAllDay: Bool = false,
    type: EventType = .event(.accepted)
) -> EventModel {
    EventModel(
        id: id,
        start: start,
        end: end,
        title: "Design review",
        location: nil,
        notes: nil,
        url: nil,
        isAllDay: isAllDay,
        type: type,
        calendar: CalendarModel(
            id: "calendar",
            account: "Tests",
            title: "Tests",
            color: .systemRed,
            isSubscribed: false,
            isReminder: type.isReminder
        ),
        participants: [],
        timeZone: nil,
        hasRecurrenceRules: false,
        priority: nil
    )
}

@MainActor
private func assertStack(
    _ stack: ActivityLivePresentationStack,
    contains expectedIDs: [ActivityID],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(activityIDs(in: stack), expectedIDs, file: file, line: line)
}

@MainActor
private func activityIDs(in stack: ActivityLivePresentationStack) -> [ActivityID] {
    switch stack {
    case .none:
        return []
    case .full(let activity):
        return [activity.id]
    case .split(let leading, let trailing):
        return [leading.id, trailing.id]
    }
}

@MainActor
private final class TestActivity: NotchActivity {
    let id: ActivityID
    let metadata: ActivityMetadata

    @Published var isAvailable = true
    @Published var isActive = false

    init(id: String, name: String) {
        self.id = ActivityID(id)
        metadata = ActivityMetadata(name: name, systemImage: "circle")
    }

    func makeExpandedView() -> some View {
        Text(metadata.name)
    }
}

@MainActor
private final class LiveTestActivity: NotchActivity {
    let id: ActivityID
    let metadata: ActivityMetadata

    @Published var isAvailable: Bool
    @Published var isActive: Bool
    @Published var livePresentationState: ActivityLivePresentationState

    init(
        id: String,
        state: ActivityLivePresentationState,
        isAvailable: Bool = true,
        isActive: Bool = false
    ) {
        self.id = ActivityID(id)
        metadata = ActivityMetadata(name: id, systemImage: "circle")
        self.isAvailable = isAvailable
        self.isActive = isActive
        livePresentationState = state
    }

    func makeExpandedView() -> some View {
        Text(metadata.name)
    }

    func makeLivePresentationView() -> some View {
        Text(metadata.name)
    }
}
