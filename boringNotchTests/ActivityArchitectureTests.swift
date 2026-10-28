import AppKit
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
        let second = TestActivity(
            id: "second",
            name: "Second",
            summary: "Second activity summary"
        )
        let registry = try ActivityRegistry {
            first
            second
        }

        XCTAssertEqual(registry.activities.map(\.id), [first.id, second.id])
        XCTAssertEqual(registry.activity(for: second.id)?.metadata.name, "Second")
        XCTAssertNil(registry.activity(for: first.id)?.metadata.summary)
        XCTAssertEqual(
            registry.activity(for: second.id)?.metadata.summary,
            "Second activity summary"
        )
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

    func testUserEnablementIsDistinctFromRegistrationAndRuntimeAvailability() throws {
        let enabled = TestActivity(id: "enabled", name: "Enabled")
        let unavailable = TestActivity(id: "unavailable", name: "Unavailable")
        unavailable.isAvailable = false
        let enablementStore = ActivityEnablementStore()
        let registry = try ActivityRegistry(enablementStore: enablementStore) {
            enabled
            unavailable
        }

        XCTAssertEqual(registry.activities.map(\.id), [enabled.id, unavailable.id])
        XCTAssertEqual(registry.enabledActivities.map(\.id), [enabled.id, unavailable.id])
        XCTAssertEqual(registry.availableActivityIDs, [enabled.id])

        registry.setActivityEnabled(false, for: enabled.id)

        XCTAssertEqual(registry.activities.map(\.id), [enabled.id, unavailable.id])
        XCTAssertEqual(registry.enabledActivities.map(\.id), [unavailable.id])
        XCTAssertTrue(registry.availableActivityIDs.isEmpty)
        XCTAssertFalse(registry.isActivityEnabled(enabled.id))
        XCTAssertFalse(registry.isActivityAvailable(enabled.id))
        XCTAssertEqual(
            resolvedNotchView(
                .activity(enabled.id),
                availableActivityIDs: registry.availableActivityIDs,
                includesShelf: false
            ),
            .home
        )
    }

    func testDisabledConfigurableActivityRemainsRegisteredAndConfigurable() throws {
        let activity = ConfigurableTestActivity(id: "configurable")
        let registry = try ActivityRegistry(enablementStore: ActivityEnablementStore()) {
            activity
        }

        registry.setActivityEnabled(false, for: activity.id)

        let registered = try XCTUnwrap(registry.activity(for: activity.id))
        XCTAssertEqual(registry.activities.map(\.id), [activity.id])
        XCTAssertFalse(registry.isActivityEnabled(activity.id))
        XCTAssertTrue(registered.supportsConfiguration)
        let _: AnyView = registered.makeConfigurationView()
    }

    func testEnablementStorePersistsDisabledActivityIDs() {
        let first = ActivityID("first")
        let second = ActivityID("second")
        var persistedValues: [[String]] = []
        let store = ActivityEnablementStore { persistedValues.append($0) }

        store.setEnabled(false, for: second)
        store.setEnabled(false, for: first)
        store.setEnabled(true, for: second)

        XCTAssertEqual(persistedValues, [["second"], ["first", "second"], ["first"]])
        XCTAssertFalse(store.isEnabled(first))
        XCTAssertTrue(store.isEnabled(second))
    }

    func testChinVisibilityStorePersistsHiddenActivityIDs() {
        let first = ActivityID("first")
        let second = ActivityID("second")
        var persistedValues: [[String]] = []
        let store = ActivityChinVisibilityStore { persistedValues.append($0) }

        store.setShown(false, for: second)
        store.setShown(false, for: first)
        store.setShown(true, for: second)

        XCTAssertEqual(persistedValues, [["second"], ["first", "second"], ["first"]])
        XCTAssertFalse(store.isShown(first))
        XCTAssertTrue(store.isShown(second))
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

    func testDisablingRegisteredActivityRemovesAndReenablesLiveEligibility() async throws {
        let activity = LiveTestActivity(
            id: "toggle-live",
            state: .visible(priority: .normal)
        )
        let enablementStore = ActivityEnablementStore()
        let activityRegistry = try ActivityRegistry(enablementStore: enablementStore) {
            activity
        }
        let liveRegistry = LiveActivityPresentationProviderRegistry(
            activityRegistry: activityRegistry
        )
        let coordinator = ActivityLivePresentationCoordinator(registry: liveRegistry)

        assertStack(selectedStack(from: liveRegistry, coordinator: coordinator), contains: [activity.id])

        activityRegistry.setActivityEnabled(false, for: activity.id)
        await coordinator.waitForPendingReconciliation()
        XCTAssertTrue(liveRegistry.providers.isEmpty)
        assertStack(selectedStack(from: liveRegistry, coordinator: coordinator), contains: [])
        XCTAssertNil(coordinator.snapshot.startedSequence(for: activity.id))

        activityRegistry.setActivityEnabled(true, for: activity.id)
        await coordinator.waitForPendingReconciliation()
        XCTAssertEqual(liveRegistry.providers.map(\.id), [activity.id])
        assertStack(selectedStack(from: liveRegistry, coordinator: coordinator), contains: [activity.id])
        XCTAssertNotNil(coordinator.snapshot.startedSequence(for: activity.id))
    }

    func testHidingRegisteredActivityFromChinKeepsItAvailableButRemovesLiveEligibility() async throws {
        let activity = LiveTestActivity(
            id: "toggle-chin",
            state: .visible(priority: .normal)
        )
        let activityRegistry = try ActivityRegistry(
            enablementStore: ActivityEnablementStore(),
            chinVisibilityStore: ActivityChinVisibilityStore()
        ) {
            activity
        }
        let liveRegistry = LiveActivityPresentationProviderRegistry(
            activityRegistry: activityRegistry
        )
        let coordinator = ActivityLivePresentationCoordinator(registry: liveRegistry)

        XCTAssertEqual(activityRegistry.availableActivityIDs, [activity.id])
        assertStack(selectedStack(from: liveRegistry, coordinator: coordinator), contains: [activity.id])

        activityRegistry.setActivityShownOnChin(false, for: activity.id)
        await coordinator.waitForPendingReconciliation()

        XCTAssertTrue(activityRegistry.isActivityEnabled(activity.id))
        XCTAssertEqual(activityRegistry.availableActivityIDs, [activity.id])
        XCTAssertFalse(activityRegistry.isActivityShownOnChin(activity.id))
        XCTAssertTrue(liveRegistry.providers.isEmpty)
        assertStack(selectedStack(from: liveRegistry, coordinator: coordinator), contains: [])
        XCTAssertNil(coordinator.snapshot.startedSequence(for: activity.id))

        activityRegistry.setActivityShownOnChin(true, for: activity.id)
        await coordinator.waitForPendingReconciliation()

        XCTAssertEqual(liveRegistry.providers.map(\.id), [activity.id])
        assertStack(selectedStack(from: liveRegistry, coordinator: coordinator), contains: [activity.id])
        XCTAssertNotNil(coordinator.snapshot.startedSequence(for: activity.id))
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

    func testSelectedLivePresentationStackReportsRequiredClosedWidth() throws {
        let accessorySize: CGFloat = 20
        let fullProvider = LiveTestProvider(
            id: ActivityID("full"),
            state: .visible(priority: .normal),
            livePresentationSizing: LiveActivityPresentationSizing(
                fullContentWidth: .fixed(42),
                minimalContentWidth: .fixed(17)
            )
        )

        let fullStack = selectedActivityLivePresentationStack(
            from: [AnyLiveActivityPresentationProvider(fullProvider)],
            snapshot: .empty
        )

        XCTAssertEqual(
            fullStack.requiredAdditionalWidth(accessorySize: accessorySize),
            ((42 + closedActivityFullPresentationContentLeadingPadding) * 2) + 36
        )

        let mediaProvider = LiveTestProvider(
            id: .media,
            state: .visible(priority: .normal),
            livePresentationSizing: LiveActivityPresentationSizing(
                fullContentWidth: .accessorySize,
                minimalContentWidth: .accessorySize
            )
        )
        let mediaStack = selectedActivityLivePresentationStack(
            from: [AnyLiveActivityPresentationProvider(mediaProvider)],
            snapshot: .empty
        )

        XCTAssertEqual(
            mediaStack.requiredAdditionalWidth(accessorySize: accessorySize),
            ((accessorySize + closedActivityFullPresentationContentLeadingPadding) * 2) + 36
        )

        let leadingProvider = LiveTestProvider(
            id: ActivityID("leading"),
            state: .visible(priority: .normal),
            livePresentationSizing: LiveActivityPresentationSizing(
                minimalContentWidth: .fixed(30)
            )
        )
        let trailingProvider = LiveTestProvider(
            id: ActivityID("trailing"),
            state: .visible(priority: .normal),
            showsAccessoryInMinimalPresentation: false,
            livePresentationSizing: LiveActivityPresentationSizing(
                minimalContentWidth: .accessorySize
            )
        )

        let splitStack = selectedActivityLivePresentationStack(
            from: [
                AnyLiveActivityPresentationProvider(leadingProvider),
                AnyLiveActivityPresentationProvider(trailingProvider)
            ],
            snapshot: ActivityLivePresentationSnapshot(startedSequences: [
                leadingProvider.id: 1,
                trailingProvider.id: 2
            ])
        )

        XCTAssertEqual(
            splitStack.requiredAdditionalWidth(accessorySize: accessorySize),
            2 * (30 + accessorySize + 6) + 36
        )

        let iconOnlyProvider = LiveTestProvider(
            id: ActivityID("icon-only"),
            state: .visible(priority: .normal),
            livePresentationSizing: LiveActivityPresentationSizing(
                minimalContentWidth: .fixed(0)
            )
        )
        let contentOnlyProvider = LiveTestProvider(
            id: ActivityID("content-only"),
            state: .visible(priority: .normal),
            showsAccessoryInMinimalPresentation: false,
            livePresentationSizing: LiveActivityPresentationSizing(
                minimalContentWidth: .fixed(12)
            )
        )
        let iconOnlyStack = selectedActivityLivePresentationStack(
            from: [
                AnyLiveActivityPresentationProvider(iconOnlyProvider),
                AnyLiveActivityPresentationProvider(contentOnlyProvider)
            ],
            snapshot: ActivityLivePresentationSnapshot(startedSequences: [
                iconOnlyProvider.id: 1,
                contentOnlyProvider.id: 2
            ])
        )

        XCTAssertEqual(
            iconOnlyStack.requiredAdditionalWidth(accessorySize: accessorySize),
            2 * accessorySize + 36
        )
    }

    func testClosedActivityNotchEdgeSpacingScalesAndCaps() {
        XCTAssertEqual(closedActivityNotchEdgeSpacing(accessorySize: 0), 0)
        XCTAssertEqual(closedActivityNotchEdgeSpacing(accessorySize: 10), 2)
        XCTAssertEqual(closedActivityNotchEdgeSpacing(accessorySize: 20), 4)
        XCTAssertEqual(closedActivityNotchEdgeSpacing(accessorySize: 40), 4)
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

    func testMediaStartPublishesOnlyTheResolvedSplitOrder() async throws {
        let companion = LiveTestActivity(id: ActivityID.doberman.rawValue, state: .visible(priority: .low))
        let activities = try ActivityRegistry { companion }
        let media = LiveTestProvider(id: .media)
        let providers = LiveActivityPresentationProviderRegistry(
            activityRegistry: activities,
            additionalProviders: [AnyLiveActivityPresentationProvider(media)]
        )
        let coordinator = ActivityLivePresentationCoordinator(registry: providers)
        var selections: [String] = []
        var sequences: [Int?] = []
        let observation = coordinator.$presentation.dropFirst().sink { resolved in
            selections.append(resolved.stack.identity)
            sequences.append(resolved.snapshot.startedSequence(for: .media))
        }
        defer { observation.cancel() }

        media.livePresentationState = .visible(priority: .normal)
        // Before the batch commits, keep the previous composition rather than
        // combining new eligibility with the previous recency snapshot.
        assertStack(coordinator.selectedStack, contains: [.doberman])
        await coordinator.waitForPendingReconciliation()

        XCTAssertEqual(selections, ["split:builtin.doberman:builtin.media"])
        XCTAssertEqual(sequences.count, 1)
        XCTAssertNotNil(sequences[0])
        assertStack(coordinator.selectedStack, contains: [.doberman, .media])

        media.livePresentationState = .visible(priority: .low)
        media.objectWillChange.send() // Artwork and progress do not restart selection.
        await coordinator.waitForPendingReconciliation()
        XCTAssertEqual(selections.count, 1)
    }

    func testEligibilityBatchDoesNotPublishTemporaryFullMedia() async throws {
        let companion = LiveTestActivity(id: ActivityID.doberman.rawValue, state: .visible(priority: .low))
        let activities = try ActivityRegistry { companion }
        let media = LiveTestProvider(id: .media, state: .visible(priority: .normal))
        let providers = LiveActivityPresentationProviderRegistry(
            activityRegistry: activities,
            additionalProviders: [AnyLiveActivityPresentationProvider(media)]
        )
        let coordinator = ActivityLivePresentationCoordinator(registry: providers)
        let initialIdentity = coordinator.selectedStack.identity
        var selections: [String] = []
        let observation = coordinator.$presentation.dropFirst().sink { selections.append($0.stack.identity) }
        defer { observation.cancel() }

        companion.livePresentationState = .hidden
        media.objectWillChange.send()
        companion.livePresentationState = .visible(priority: .low)
        await coordinator.waitForPendingReconciliation()

        XCTAssertEqual(coordinator.selectedStack.identity, initialIdentity)
        XCTAssertTrue(selections.isEmpty)
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
        XCTAssertEqual(calendar.metadata.summary, "View upcoming events and reminders.")
        XCTAssertEqual(calendar.metadata.preferredExpandedHeight, calendarOpenNotchHeight)
        XCTAssertTrue(calendar.supportsConfiguration)
        XCTAssertFalse(calendar.supportsCompactPresentation)
        XCTAssertEqual(calendar.livePresentationState, .hidden)
    }

    func testTimerAndMediaAdaptersRemainOutsideOpenNotchNavigation() throws {
        let registry = try ActivityRegistry {
            TestActivity(id: "registered", name: "Registered")
        }
        let time = LiveTestProvider(id: .time)
        let media = LiveTestProvider(id: .media)
        let liveRegistry = LiveActivityPresentationProviderRegistry(
            activityRegistry: registry,
            additionalProviders: [
                AnyLiveActivityPresentationProvider(time),
                AnyLiveActivityPresentationProvider(media)
            ]
        )

        XCTAssertEqual(registry.availableActivityIDs, [ActivityID("registered")])
        XCTAssertEqual(
            liveRegistry.providers.map(\.id),
            [ActivityID("registered"), .time, .media]
        )
        XCTAssertEqual(
            visibleNotchViews(
                availableActivityIDs: registry.availableActivityIDs,
                includesShelf: false
            ),
            [.home, .activity(ActivityID("registered")), .activities]
        )

        registry.setActivityEnabled(false, for: ActivityID("registered"))

        XCTAssertEqual(liveRegistry.providers.map(\.id), [.time, .media])
    }

    func testUnifiedProvidersUseOneRecencyAndPromotionFlow() async throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let suiteName = "UnifiedLiveProviders.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let pomodoroManager = PomodoroManager(
            defaults: defaults,
            now: { now },
            configuration: { .standard },
            managesBackgroundExecution: false
        )
        let timeManager = TimeActivityManager(
            defaults: defaults,
            now: { now },
            observeLifecycle: false,
            playCompletionSound: {}
        )
        let media = LiveTestProvider(id: .media)
        let activityRegistry = try ActivityRegistry {
            PomodoroActivity(manager: pomodoroManager)
        }
        let liveRegistry = LiveActivityPresentationProviderRegistry(
            activityRegistry: activityRegistry,
            additionalProviders: [
                AnyLiveActivityPresentationProvider(
                    TimeLiveActivityProvider(manager: timeManager, isEnabled: true)
                ),
                AnyLiveActivityPresentationProvider(media)
            ]
        )
        let coordinator = ActivityLivePresentationCoordinator(registry: liveRegistry)

        pomodoroManager.start()
        await coordinator.waitForPendingReconciliation()
        assertStack(selectedStack(from: liveRegistry, coordinator: coordinator), contains: [.pomodoro])
        let pomodoroSequence = try XCTUnwrap(
            coordinator.snapshot.startedSequence(for: .pomodoro)
        )

        XCTAssertTrue(timeManager.startTimer(duration: 60))
        await coordinator.waitForPendingReconciliation()
        assertStack(
            selectedStack(from: liveRegistry, coordinator: coordinator),
            contains: [.pomodoro, .time]
        )
        let timeSequence = try XCTUnwrap(coordinator.snapshot.startedSequence(for: .time))
        XCTAssertGreaterThan(timeSequence, pomodoroSequence)

        timeManager.pause()
        await coordinator.waitForPendingReconciliation()
        XCTAssertEqual(coordinator.snapshot.startedSequence(for: .time), timeSequence)

        media.livePresentationState = .visible(priority: .normal)
        await coordinator.waitForPendingReconciliation()
        assertStack(
            selectedStack(from: liveRegistry, coordinator: coordinator),
            contains: [.time, .media]
        )
        let mediaSequence = try XCTUnwrap(coordinator.snapshot.startedSequence(for: .media))

        media.livePresentationState = .visible(priority: .low)
        await coordinator.waitForPendingReconciliation()
        XCTAssertEqual(coordinator.snapshot.startedSequence(for: .media), mediaSequence)

        timeManager.reset()
        await coordinator.waitForPendingReconciliation()
        assertStack(
            selectedStack(from: liveRegistry, coordinator: coordinator),
            contains: [.pomodoro, .media]
        )

        media.livePresentationState = .hidden
        await coordinator.waitForPendingReconciliation()
        assertStack(selectedStack(from: liveRegistry, coordinator: coordinator), contains: [.pomodoro])
    }

    func testTimerAndMediaEligibilitySemanticsDoNotCreateFalseRestarts() throws {
        let now = Date(timeIntervalSince1970: 30_000)
        var running = try XCTUnwrap(TimeActivitySnapshot.timer(duration: 60, startedAt: now))

        XCTAssertEqual(
            TimeLiveActivityProvider.presentationState(snapshot: running, isEnabled: true),
            .visible(priority: .normal)
        )
        running.pause(at: now.addingTimeInterval(10))
        XCTAssertEqual(
            TimeLiveActivityProvider.presentationState(snapshot: running, isEnabled: true),
            .visible(priority: .low)
        )
        running.finish()
        XCTAssertEqual(
            TimeLiveActivityProvider.presentationState(snapshot: running, isEnabled: true),
            .hidden
        )

        XCTAssertEqual(
            MediaLiveActivityProvider.presentationState(
                isEnabled: true,
                isPlaying: true,
                isPlayerIdle: false
            ),
            .visible(priority: .normal)
        )
        XCTAssertEqual(
            MediaLiveActivityProvider.presentationState(
                isEnabled: true,
                isPlaying: false,
                isPlayerIdle: false
            ),
            .visible(priority: .low)
        )
        XCTAssertEqual(
            MediaLiveActivityProvider.presentationState(
                isEnabled: true,
                isPlaying: false,
                isPlayerIdle: true
            ),
            .hidden
        )
    }

    func testTimeProviderMinimalPresentationUsesAccessoryOnlySizing() throws {
        let accessorySize: CGFloat = 20
        let now = Date(timeIntervalSince1970: 40_000)
        let suiteName = "TimeProviderMinimalSizing.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = TimeActivityManager(
            defaults: defaults,
            now: { now },
            observeLifecycle: false,
            playCompletionSound: {}
        )
        XCTAssertTrue(manager.startTimer(duration: 60))

        let timeProvider = TimeLiveActivityProvider(manager: manager, isEnabled: true)
        let contentProvider = LiveTestProvider(
            id: ActivityID("content-only"),
            state: .visible(priority: .normal),
            showsAccessoryInMinimalPresentation: false,
            livePresentationSizing: LiveActivityPresentationSizing(
                minimalContentWidth: .fixed(12)
            )
        )
        let stack = selectedActivityLivePresentationStack(
            from: [
                AnyLiveActivityPresentationProvider(timeProvider),
                AnyLiveActivityPresentationProvider(contentProvider)
            ],
            snapshot: ActivityLivePresentationSnapshot(startedSequences: [
                .time: 2,
                contentProvider.id: 1
            ])
        )

        XCTAssertEqual(
            stack.requiredAdditionalWidth(accessorySize: accessorySize),
            2 * accessorySize + 36
        )
    }

    func testTimeProviderFullPresentationUsesCompactSizingForSubHourTimers() throws {
        let now = Date(timeIntervalSince1970: 40_000)
        let suiteName = "TimeProviderFullSizing.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = TimeActivityManager(
            defaults: defaults,
            now: { now },
            observeLifecycle: false,
            playCompletionSound: {}
        )
        let timeProvider = TimeLiveActivityProvider(manager: manager, isEnabled: true)

        XCTAssertTrue(manager.startTimer(duration: 10 * 60))
        XCTAssertEqual(
            timeProvider.livePresentationSizing.fullContentWidth,
            .fixed(closedTimeActivityCompactTextWidth)
        )

        manager.reset()

        XCTAssertTrue(manager.startTimer(duration: 90 * 60))
        XCTAssertEqual(
            timeProvider.livePresentationSizing.fullContentWidth,
            .fixed(closedTimeActivityMinimumTextWidth)
        )
    }

    func testTransientInterruptionPreservesSelectedStackInDiagnostics() throws {
        let provider = LiveTestProvider(
            id: .pomodoro,
            state: .visible(priority: .normal)
        )
        let activityRegistry = try ActivityRegistry { }
        let liveRegistry = LiveActivityPresentationProviderRegistry(
            activityRegistry: activityRegistry,
            additionalProviders: [AnyLiveActivityPresentationProvider(provider)]
        )
        let stack = selectedActivityLivePresentationStack(
            from: liveRegistry.providers,
            snapshot: .empty
        )

        XCTAssertEqual(
            closedNotchLivePresentationDisplayDescription(
                for: stack,
                isNotchClosed: true,
                hidesOnClosed: false,
                interruption: .battery
            ),
            "selected=.full(builtin.pomodoro) display=.interrupted(battery)"
        )
        XCTAssertEqual(
            closedNotchLivePresentationDisplayDescription(
                for: stack,
                isNotchClosed: true,
                hidesOnClosed: false,
                interruption: .mediaNotification
            ),
            "selected=.full(builtin.pomodoro) display=.interrupted(media-notification)"
        )
    }
}

@MainActor
private func selectedStack(
    from registry: LiveActivityPresentationProviderRegistry,
    coordinator: ActivityLivePresentationCoordinator
) -> ActivityLivePresentationStack {
    coordinator.selectedStack
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

    init(id: String, name: String, summary: String? = nil) {
        self.id = ActivityID(id)
        metadata = ActivityMetadata(name: name, systemImage: "circle", summary: summary)
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

@MainActor
private final class ConfigurableTestActivity: NotchActivity {
    let id: ActivityID
    let metadata: ActivityMetadata

    init(id: String) {
        self.id = ActivityID(id)
        metadata = ActivityMetadata(name: id, systemImage: "slider.horizontal.3")
    }

    var supportsConfiguration: Bool { true }

    func makeExpandedView() -> some View {
        Text(metadata.name)
    }

    func makeConfigurationView() -> some View {
        Text("Configuration")
    }
}

@MainActor
private final class LiveTestProvider: LiveActivityPresentationProvider {
    let id: ActivityID
    let name: String
    let showsAccessoryInMinimalPresentation: Bool
    let livePresentationSizing: LiveActivityPresentationSizing
    @Published var livePresentationState: ActivityLivePresentationState

    init(
        id: ActivityID,
        state: ActivityLivePresentationState = .hidden,
        showsAccessoryInMinimalPresentation: Bool = true,
        livePresentationSizing: LiveActivityPresentationSizing = LiveActivityPresentationSizing()
    ) {
        self.id = id
        name = id.rawValue
        livePresentationState = state
        self.showsAccessoryInMinimalPresentation = showsAccessoryInMinimalPresentation
        self.livePresentationSizing = livePresentationSizing
    }

    func makeAccessoryView() -> some View {
        Image(systemName: "circle")
    }

    func makeFullView() -> some View {
        Text(name)
    }

    func makeMinimalView() -> some View {
        Text(name)
    }
}


@MainActor
final class FloatingTabBarTests: XCTestCase {
    func testAllCurrentTabsFitFullWidthWithXM6Selected() {
        let width = FloatingTabBarMetrics.contentWidth(tabCount: 8, selectedLabel: "XM6")
        XCTAssertLessThan(width, openNotchSize.width - 40)
        XCTAssertEqual(FloatingTabBarMetrics.viewportWidth(contentWidth: width, availableWidth: 600), width)
    }

    func testOverflowReservesMenuSpaceAndCanFitSelectedBubble() {
        let contentWidth = FloatingTabBarMetrics.contentWidth(tabCount: 20, selectedLabel: "XM6")
        let viewport = FloatingTabBarMetrics.viewportWidth(contentWidth: contentWidth, availableWidth: 300)
        XCTAssertGreaterThan(contentWidth, 300)
        XCTAssertEqual(viewport, 252)
        XCTAssertGreaterThan(viewport, FloatingTabBarMetrics.labelWidth("XM6") + 51)
        XCTAssertEqual(FloatingTabBarMetrics.viewportWidth(contentWidth: contentWidth, availableWidth: 20), 0)
    }

    func testLongSelectedNamesCannotPushCurrentTabsIntoOverflow() {
        let label = String(repeating: "Long extension name ", count: 20)
        XCTAssertEqual(FloatingTabBarMetrics.labelWidth(label), 100)
        XCTAssertLessThan(FloatingTabBarMetrics.contentWidth(tabCount: 8, selectedLabel: label), 600)
        XCTAssertEqual(FloatingTabBarMetrics.contentWidth(tabCount: 0, selectedLabel: nil), 0)
    }

    func testHoverRegionIncludesDetachedDockAndGapOnlyWhileOpen() {
        let vm = BoringViewModel()
        let oldTabs = vm.coordinator.alwaysShowTabs
        defer { vm.coordinator.alwaysShowTabs = oldTabs }
        vm.coordinator.alwaysShowTabs = true
        vm.open()
        vm.updateOpenNotchHeight(300)
        guard let screen = NSScreen.main else { return XCTFail("No screen for notch hover test") }
        let y = screen.frame.maxY - vm.notchSize.height - floatingTabBarGap - 20
        XCTAssertEqual(vm.floatingTabBarReservedHeight, 56)
        XCTAssertTrue(vm.isMouseHovering(position: NSPoint(x: screen.frame.midX, y: y)))
        XCTAssertFalse(vm.isMouseHovering(position: NSPoint(x: screen.frame.midX, y: screen.frame.maxY - 370)))
        vm.close()
        XCTAssertEqual(vm.floatingTabBarReservedHeight, 0)
        XCTAssertFalse(vm.isMouseHovering(position: NSPoint(x: screen.frame.midX, y: y)))
    }
}


final class NotchSurfaceStyleTests: XCTestCase {
    func testBlackIsDefaultAndGlassChoicePersists() throws {
        let suiteName = "NotchSurfaceStyleTests.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }
        let key = Defaults.Key<NotchSurfaceStyle>("notchSurfaceStyle", default: .solidBlack, suite: suite)
        XCTAssertEqual(Defaults[key], .solidBlack)
        Defaults[key] = .siriGlass
        let restored = Defaults.Key<NotchSurfaceStyle>("notchSurfaceStyle", default: .solidBlack, suite: suite)
        XCTAssertEqual(Defaults[restored], .siriGlass)
        Defaults[key] = .solidBlack
        XCTAssertEqual(Defaults[restored], .solidBlack)
    }

    func testGlassOnlyAppliesToExpandedPanelWithoutReducedTransparency() {
        XCTAssertTrue(NotchSurfaceStyle.siriGlass.usesGlass(isOpen: true, reduceTransparency: false))
        XCTAssertFalse(NotchSurfaceStyle.siriGlass.usesGlass(isOpen: false, reduceTransparency: false))
        XCTAssertFalse(NotchSurfaceStyle.siriGlass.usesGlass(isOpen: true, reduceTransparency: true))
        XCTAssertFalse(NotchSurfaceStyle.solidBlack.usesGlass(isOpen: true, reduceTransparency: false))
    }
}

@MainActor
final class NotchWindowHeightRetentionTests: XCTestCase {
    func testClosingKeepsDockUnclippedUntilExitFinishes() async throws {
        let sizing = NotchWindowHeightRetention(initialHeight: 376, shrinkDelay: .milliseconds(15))
        sizing.update(210, reduceMotion: false)
        XCTAssertEqual(sizing.height, 376)
        try await Task.sleep(for: .milliseconds(45))
        XCTAssertEqual(sizing.height, 210)
    }

    func testRapidReopenCancelsPendingWindowShrink() async throws {
        let sizing = NotchWindowHeightRetention(initialHeight: 376, shrinkDelay: .milliseconds(15))
        sizing.update(210, reduceMotion: false)
        sizing.update(400, reduceMotion: false)
        try await Task.sleep(for: .milliseconds(45))
        XCTAssertEqual(sizing.height, 400)
    }

    func testLatestClosingSizeWinsAcrossTabHeightChanges() async throws {
        let sizing = NotchWindowHeightRetention(initialHeight: 376, shrinkDelay: .milliseconds(15))
        sizing.update(266, reduceMotion: false)
        sizing.update(210, reduceMotion: false)
        try await Task.sleep(for: .milliseconds(45))
        XCTAssertEqual(sizing.height, 210)
    }

    func testReducedMotionAndCancellationDoNotLeaveDelayedResize() async throws {
        let sizing = NotchWindowHeightRetention(initialHeight: 376, shrinkDelay: .milliseconds(15))
        sizing.update(210, reduceMotion: false)
        sizing.update(266, reduceMotion: true)
        XCTAssertEqual(sizing.height, 266)
        try await Task.sleep(for: .milliseconds(45))
        XCTAssertEqual(sizing.height, 266)
        sizing.update(210, reduceMotion: false)
        sizing.cancel()
        try await Task.sleep(for: .milliseconds(45))
        XCTAssertEqual(sizing.height, 266)
    }
}

@MainActor
final class NotchSafeZoneTests: XCTestCase {
    func testHardwareCutoutHasClearanceEvenWithCustomClosedSize() {
        XCTAssertEqual(protectedNotchCenterWidth(closedWidth: 185, hardwareWidth: 181), 197)
        XCTAssertEqual(protectedNotchCenterWidth(closedWidth: 120, hardwareWidth: 210), 226)
        XCTAssertEqual(protectedNotchCenterWidth(closedWidth: 240, hardwareWidth: 181), 240)
        XCTAssertEqual(protectedNotchCenterWidth(closedWidth: 185, hardwareWidth: nil), 185)
    }

    func testRenderedUnequalActivitiesLeaveTheHardwareCenterEmpty() throws {
        let centerWidth: CGFloat = 200
        for (leading, trailing): (CGFloat, CGFloat) in [(36, 70), (70, 36), (182, 100)] {
            let hosting = NSHostingView(rootView:
                NotchSafeZoneLayout(centerWidth: centerWidth, spacing: 4) {
                    Color.red.frame(width: leading, height: 32)
                    Color.black.frame(width: centerWidth, height: 32)
                    Color.green.frame(width: trailing, height: 32)
                }
                .frame(width: 600, height: 32)
                .background(.blue)
            )
            hosting.sizingOptions = []
            let window = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 600, height: 32),
                                 styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            defer { window.close() }
            hosting.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / hosting.bounds.width
            let midX = bitmap.pixelsWide / 2
            let halfCenter = Int(centerWidth * scale / 2)
            for x in (midX - halfCenter)..<(midX + halfCenter) {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
                XCTAssertLessThan(color.redComponent + color.greenComponent + color.blueComponent, 0.05,
                                  "Activity content entered safe zone at x=\(x), sides \(leading)/\(trailing)")
                XCTAssertGreaterThan(color.alphaComponent, 0.95)
            }
            let left = try XCTUnwrap(bitmap.colorAt(x: midX - halfCenter - Int(6 * scale), y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
            let right = try XCTUnwrap(bitmap.colorAt(x: midX + halfCenter + Int(6 * scale), y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
            XCTAssertGreaterThan(left.redComponent, 0.7)
            XCTAssertGreaterThan(right.greenComponent, 0.7)
        }
    }
}

@MainActor
final class NotchTopAnchorTests: XCTestCase {
    func testRenderedNotchStaysAttachedThroughoutOpenAndClose() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let vm = BoringViewModel(screenUUID: screen.displayUUID)
        vm.hideOnClosed = false
        let oldStyle = Defaults[.notchSurfaceStyle]
        let oldTabs = vm.coordinator.alwaysShowTabs
        let oldView = vm.coordinator.currentView
        Defaults[.notchSurfaceStyle] = .solidBlack
        vm.coordinator.alwaysShowTabs = true
        vm.coordinator.currentView = .activity(.xm6)
        let window = BoringNotchSkyLightWindow(
            contentRect: CGRect(x: screen.frame.midX - 320, y: screen.frame.maxY - 210, width: 640, height: 210),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered, defer: false
        )
        let hosting = NSHostingView(rootView: NotchWindowRoot(viewModel: vm))
        window.bindSizing(to: vm)
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        window.contentView = hosting
        window.orderFrontRegardless()
        defer {
            window.close()
            vm.destroy()
            Defaults[.notchSurfaceStyle] = oldStyle
            vm.coordinator.alwaysShowTabs = oldTabs
            vm.coordinator.currentView = oldView
        }
        try await Task.sleep(for: .milliseconds(100))
        let transitions: [(isOpen: Bool, height: CGFloat, samples: Int)] = [
            (true, openNotchSize.height, 25),
            (false, 0, 25),
            (true, 300, 25),
            (false, 0, 3), // Reopen before the retained window can shrink.
            (true, maximumOpenNotchHeight, 25),
            (false, 0, 25)
        ]
        for (isOpen, height, samples) in transitions {
            if isOpen {
                // The center selects media; a side selects its live activity.
                // Selection starts its own animation before hover opens the shell.
                withAnimation(.smooth(duration: 0.25)) {
                    vm.coordinator.currentView = height == 300 ? .activity(.xm6) : .home
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.72)) {
                if isOpen {
                    vm.open()
                    if vm.coordinator.currentView == .activity(.xm6) {
                        XCTAssertEqual(vm.notchSize.height, 300)
                    }
                    vm.updateOpenNotchHeight(height)
                    XCTAssertGreaterThanOrEqual(window.frame.height,
                                                notchWindowHeight(for: vm.notchSize.height) + vm.floatingTabBarReservedHeight)
                } else {
                    vm.close()
                }
            }
            for sample in 0..<samples {
                try await Task.sleep(for: .milliseconds(20))
                hosting.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                let topPixel = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 0))
                XCTAssertGreaterThan(topPixel.alphaComponent, 0.95, "Detached during \(isOpen ? "opening" : "closing"), height \(height), sample \(sample)")
                XCTAssertEqual(window.frame.maxY, screen.frame.maxY, accuracy: 0.5)
            }
        }
    }

    func testEveryOpenCloseHeightKeepsTheScreenTopAndHorizontalPosition() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        var frame = CGRect(x: 640, y: 870, width: 640, height: 210)
        for height: CGFloat in [266, 376, 396, 266, 210, 376, 210] {
            frame = topAnchoredNotchWindowFrame(frame, height: height, screenFrame: screen)
            XCTAssertEqual(frame.maxY, screen.maxY)
            XCTAssertEqual(frame.minX, 640)
            XCTAssertEqual(frame.width, 640)
            XCTAssertEqual(frame.height, height)
        }
    }

    func testAWindowAlreadyDisplacedDownwardIsReattachedWithoutChangingHeight() {
        let screen = CGRect(x: -1920, y: 240, width: 1920, height: 1080)
        let displaced = CGRect(x: -1280, y: screen.maxY - 376 - 30, width: 640, height: 376)
        let repaired = topAnchoredNotchWindowFrame(displaced, height: 376, screenFrame: screen)
        XCTAssertEqual(repaired.maxY, screen.maxY)
        XCTAssertEqual(repaired.minX, displaced.minX)
    }

    func testSecondaryScreenBelowMainAndMissingScreenFallback() {
        let screen = CGRect(x: 1920, y: -1200, width: 1920, height: 1200)
        let original = CGRect(x: 2560, y: -210, width: 640, height: 210)
        let expanded = topAnchoredNotchWindowFrame(original, height: 396, screenFrame: screen)
        XCTAssertEqual(expanded.maxY, 0)
        let closed = topAnchoredNotchWindowFrame(expanded, height: 210, screenFrame: nil)
        XCTAssertEqual(closed.maxY, expanded.maxY)
    }

    func testNativeWindowResizeAndSameHeightRepairKeepTopEdge() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let window = BoringNotchWindow(
            contentRect: CGRect(x: screen.frame.midX - 320, y: screen.frame.maxY - 210, width: 640, height: 210),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let sizing = NotchWindowHeightSynchronizer.WindowSizingView(height: 210, screenUUID: nil)
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 640, height: 210))
        window.contentView = container
        container.addSubview(sizing)
        for height: CGFloat in [376, 266, 210] {
            sizing.updateHeight(height, screenUUID: nil)
            try await Task.sleep(for: .milliseconds(15))
            XCTAssertEqual(window.frame.maxY, screen.frame.maxY, accuracy: 0.5)
            XCTAssertEqual(window.frame.height, height, accuracy: 0.5)
        }
        window.setFrameOrigin(NSPoint(x: window.frame.minX, y: window.frame.minY - 30))
        sizing.updateHeight(210, screenUUID: nil)
        try await Task.sleep(for: .milliseconds(15))
        XCTAssertEqual(window.frame.maxY, screen.frame.maxY, accuracy: 0.5)
    }
}
