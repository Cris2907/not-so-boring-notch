import Combine
import Defaults
import SwiftUI
import XCTest
@testable import boringNotch

@MainActor
final class QuickNotesActivityTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "QuickNotesActivityTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testStableMetadataRegistrationAndConfigurationSupport() throws {
        XCTAssertEqual(QuickNotesActivity.activityID.rawValue, "builtin.quick-notes")
        XCTAssertNotNil(ActivityRegistry.shared.activity(for: .quickNotes))

        let registry = try ActivityRegistry {
            QuickNotesActivity(manager: makeManager())
        }
        let activity = try XCTUnwrap(registry.activity(for: .quickNotes))

        XCTAssertEqual(activity.metadata.name, "Quick Notes")
        XCTAssertEqual(activity.metadata.systemImage, "note.text")
        XCTAssertEqual(activity.metadata.summary, "Keep a short note close at hand.")
        XCTAssertEqual(
            activity.livePresentationSizing,
            LiveActivityPresentationSizing(
                fullContentWidth: .fixed(140),
                minimalContentWidth: .fixed(42)
            )
        )
        XCTAssertFalse(activity.supportsConfiguration)
        XCTAssertTrue(activity.isAvailable)
    }

    func testRegistrationAddsDedicatedTabAndDisablementUsesGenericFallback() throws {
        let enablementStore = ActivityEnablementStore()
        let registry = try ActivityRegistry(enablementStore: enablementStore) {
            QuickNotesActivity(manager: makeManager())
        }

        XCTAssertEqual(
            visibleNotchViews(
                availableActivityIDs: registry.availableActivityIDs,
                includesShelf: false
            ),
            [.home, .activity(.quickNotes), .activities]
        )

        registry.setActivityEnabled(false, for: .quickNotes)

        XCTAssertEqual(
            resolvedNotchView(
                .activity(.quickNotes),
                availableActivityIDs: registry.availableActivityIDs,
                includesShelf: false
            ),
            .home
        )
        XCTAssertTrue(registry.activity(for: .quickNotes)?.supportsConfiguration == false)
    }

    func testContentPersistsExactlyAndClearRemovesIt() {
        let firstManager = makeManager()
        let note = "First line\nSecond line"
        firstManager.updateNote(note)

        let restoredManager = makeManager()
        XCTAssertEqual(restoredManager.note, note)
        XCTAssertTrue(restoredManager.hasMeaningfulContent)

        restoredManager.clear()

        XCTAssertEqual(restoredManager.note, "")
        XCTAssertNil(defaults.string(forKey: "quickNotes.note"))
        XCTAssertEqual(makeManager().note, "")
    }

    func testContentIsLimitedToMaximumCharacterCountWhenUpdatedAndRestored() {
        let manager = makeManager()
        let oversizedNote = String(repeating: "a", count: QuickNotesManager.maximumCharacterCount + 40)

        manager.updateNote(oversizedNote)

        XCTAssertEqual(manager.note.count, QuickNotesManager.maximumCharacterCount)
        XCTAssertEqual(
            defaults.string(forKey: "quickNotes.note")?.count,
            QuickNotesManager.maximumCharacterCount
        )

        defaults.set(oversizedNote, forKey: "quickNotes.note")
        XCTAssertEqual(makeManager().note.count, QuickNotesManager.maximumCharacterCount)
        XCTAssertEqual(
            defaults.string(forKey: "quickNotes.note")?.count,
            QuickNotesManager.maximumCharacterCount
        )
    }

    func testContentIsLimitedToMaximumLineCountWhenUpdatedAndRestored() {
        let manager = makeManager()
        let oversizedNote = (1...(QuickNotesManager.maximumLineCount + 4))
            .map { "Line \($0)" }
            .joined(separator: "\n")

        manager.updateNote(oversizedNote)

        XCTAssertEqual(manager.note.components(separatedBy: "\n").count, QuickNotesManager.maximumLineCount)
        XCTAssertEqual(manager.note.components(separatedBy: "\n").last, "Line 10")

        defaults.set(oversizedNote, forKey: "quickNotes.note")

        let restoredManager = makeManager()
        XCTAssertEqual(restoredManager.note.components(separatedBy: "\n").count, QuickNotesManager.maximumLineCount)
        XCTAssertEqual(defaults.string(forKey: "quickNotes.note"), restoredManager.note)
    }

    func testWhitespaceIsPersistedButNotLiveEligible() throws {
        let manager = makeManager()
        let registry = try ActivityRegistry {
            QuickNotesActivity(manager: manager)
        }
        let activity = try XCTUnwrap(registry.activity(for: .quickNotes))

        manager.updateNote(" \n\t ")

        XCTAssertFalse(activity.isActive)
        XCTAssertEqual(activity.livePresentationState, .hidden)
        XCTAssertEqual(defaults.string(forKey: "quickNotes.note"), " \n\t ")

        manager.updateNote("  Remember this  ")

        XCTAssertTrue(activity.isActive)
        XCTAssertEqual(activity.livePresentationState, .visible(priority: .normal))
    }

    func testManagerChangesPropagateThroughActivityAndRegistry() throws {
        let manager = makeManager()
        let registry = try ActivityRegistry {
            QuickNotesActivity(manager: manager)
        }
        let erased = try XCTUnwrap(registry.activity(for: .quickNotes))
        var erasedUpdates = 0
        var registryUpdates = 0
        let erasedObservation = erased.objectWillChange.sink { erasedUpdates += 1 }
        let registryObservation = registry.objectWillChange.sink { registryUpdates += 1 }

        manager.updateNote("Observed")

        XCTAssertGreaterThanOrEqual(erasedUpdates, 1)
        XCTAssertGreaterThanOrEqual(registryUpdates, 1)
        withExtendedLifetime((erasedObservation, registryObservation)) {}
    }

    func testEditingNonemptyNoteDoesNotRefreshRecency() async throws {
        let manager = makeManager()
        let registry = try ActivityRegistry {
            QuickNotesActivity(manager: manager)
        }
        let coordinator = ActivityLivePresentationCoordinator(registry: registry)

        manager.updateNote("First")
        await coordinator.waitForPendingReconciliation()
        let firstSequence = try XCTUnwrap(
            coordinator.snapshot.startedSequence(for: .quickNotes)
        )

        manager.updateNote("First, revised")
        await coordinator.waitForPendingReconciliation()

        XCTAssertEqual(
            coordinator.snapshot.startedSequence(for: .quickNotes),
            firstSequence
        )

        manager.clear()
        await coordinator.waitForPendingReconciliation()
        XCTAssertNil(coordinator.snapshot.startedSequence(for: .quickNotes))

        manager.updateNote("New note")
        await coordinator.waitForPendingReconciliation()
        XCTAssertGreaterThan(
            try XCTUnwrap(coordinator.snapshot.startedSequence(for: .quickNotes)),
            firstSequence
        )
    }

    func testSingleLinePreviewNormalizesWhitespaceAndTruncatesDeterministically() {
        let manager = makeManager()
        manager.updateNote("  First line\n second\tline   ")

        XCTAssertEqual(manager.singleLinePreview(), "First line second line")
        XCTAssertEqual(manager.singleLinePreview(characterLimit: 12), "First line …")
        XCTAssertEqual(manager.singleLinePreview(characterLimit: 1), "…")
        XCTAssertEqual(manager.singleLinePreview(characterLimit: 0), "")
    }

    func testFullAndSplitSelectionUseDeclaredQuickNotesSizing() throws {
        let manager = makeManager()
        manager.updateNote("Visible")
        let quickNotes = QuickNotesActivity(manager: manager)
        let registry = try ActivityRegistry { quickNotes }

        let fullStack = selectedActivityLivePresentationStack(
            from: registry.activities,
            snapshot: .empty
        )
        switch fullStack {
        case .full(let activity):
            XCTAssertEqual(activity.id, .quickNotes)
            XCTAssertEqual(fullStack.requiredAdditionalWidth(accessorySize: 20), 188)
        default:
            XCTFail("Expected Quick Notes to use its full presentation")
        }

        let other = QuickNotesLiveTestActivity()
        let splitRegistry = try ActivityRegistry {
            quickNotes
            other
        }
        let snapshot = ActivityLivePresentationSnapshot(startedSequences: [
            .quickNotes: 1,
            other.id: 2
        ])
        let splitStack = selectedActivityLivePresentationStack(
            from: splitRegistry.activities,
            snapshot: snapshot
        )

        switch splitStack {
        case .split(let leading, let trailing):
            XCTAssertEqual(leading.id, .quickNotes)
            XCTAssertEqual(trailing.id, other.id)
            XCTAssertEqual(splitStack.requiredAdditionalWidth(accessorySize: 20), 124)
        default:
            XCTFail("Expected Quick Notes to use its minimal presentation")
        }
    }

    func testPreviewPrivacyPreferencePersists() {
        let originalValue = Defaults[.quickNotesShowContentInLivePreview]
        defer { Defaults[.quickNotesShowContentInLivePreview] = originalValue }

        Defaults[.quickNotesShowContentInLivePreview] = false
        XCTAssertFalse(Defaults[.quickNotesShowContentInLivePreview])

        Defaults[.quickNotesShowContentInLivePreview] = true
        XCTAssertTrue(Defaults[.quickNotesShowContentInLivePreview])
    }

    private func makeManager() -> QuickNotesManager {
        QuickNotesManager(defaults: defaults)
    }
}

@MainActor
private final class QuickNotesLiveTestActivity: NotchActivity {
    let id = ActivityID("test.quick-notes-peer")
    let metadata = ActivityMetadata(name: "Peer", systemImage: "circle")
    let livePresentationSizing = LiveActivityPresentationSizing(
        fullContentWidth: .fixed(20),
        minimalContentWidth: .fixed(10)
    )

    var livePresentationState: ActivityLivePresentationState {
        .visible(priority: .normal)
    }

    func makeExpandedView() -> some View { EmptyView() }
    func makeLivePresentationView() -> some View { EmptyView() }
    func makeMinimalLivePresentationView() -> some View { EmptyView() }
}
