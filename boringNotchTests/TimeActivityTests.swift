import XCTest
@testable import boringNotch

final class TimeActivitySnapshotTests: XCTestCase {
    func testTimerPauseAndResumeUsesWallClockAnchors() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        var snapshot = try XCTUnwrap(TimeActivitySnapshot.timer(duration: 120, startedAt: start))

        XCTAssertEqual(snapshot.remaining(at: start.addingTimeInterval(30)), 90, accuracy: 0.001)

        snapshot.pause(at: start.addingTimeInterval(30))
        XCTAssertEqual(snapshot.remaining(at: start.addingTimeInterval(90)), 90, accuracy: 0.001)

        snapshot.resume(at: start.addingTimeInterval(90))
        XCTAssertEqual(snapshot.remaining(at: start.addingTimeInterval(100)), 80, accuracy: 0.001)
    }

    func testStopwatchPauseAndResumeUsesAccumulatedElapsedTime() {
        let start = Date(timeIntervalSince1970: 2_000)
        var snapshot = TimeActivitySnapshot.stopwatch(startedAt: start)

        snapshot.pause(at: start.addingTimeInterval(12.5))
        XCTAssertEqual(snapshot.elapsed(at: start.addingTimeInterval(100)), 12.5, accuracy: 0.001)

        snapshot.resume(at: start.addingTimeInterval(100))
        XCTAssertEqual(snapshot.elapsed(at: start.addingTimeInterval(107.5)), 20, accuracy: 0.001)
    }

    func testTimerValidationAndFormattingAcrossHourBoundary() {
        XCTAssertFalse(TimeActivitySnapshot.isValidTimerDuration(0))
        XCTAssertTrue(TimeActivitySnapshot.isValidTimerDuration(1))
        XCTAssertTrue(TimeActivitySnapshot.isValidTimerDuration(TimeActivitySnapshot.maximumTimerDuration))
        XCTAssertFalse(TimeActivitySnapshot.isValidTimerDuration(TimeActivitySnapshot.maximumTimerDuration + 1))
        XCTAssertEqual(TimeActivityFormatter.timer(3_661), "1:01:01")
        XCTAssertEqual(TimeActivityFormatter.stopwatch(61.42, includesCentiseconds: true), "01:01.42")
    }
}

final class HorizontalSwipeAccumulatorTests: XCTestCase {
    func testThresholdTriggersOncePerGesture() {
        var accumulator = HorizontalSwipeAccumulator(threshold: 50)

        XCTAssertNil(accumulator.consume(delta: -30))
        XCTAssertEqual(accumulator.consume(delta: -25), .left)
        XCTAssertNil(accumulator.consume(delta: -100))

        accumulator.reset()
        XCTAssertEqual(accumulator.consume(delta: 50), .right)
    }

    func testDirectionReversalResetsUncommittedProgress() {
        var accumulator = HorizontalSwipeAccumulator(threshold: 50)

        XCTAssertNil(accumulator.consume(delta: -35))
        XCTAssertNil(accumulator.consume(delta: 30))
        XCTAssertEqual(accumulator.consume(delta: 25), .right)
    }

    func testDisabledGestureClearsProgress() {
        var accumulator = HorizontalSwipeAccumulator(threshold: 50)

        XCTAssertNil(accumulator.consume(delta: -40))
        XCTAssertNil(accumulator.consume(delta: -20, isEnabled: false))
        XCTAssertNil(accumulator.consume(delta: -20))
        XCTAssertEqual(accumulator.consume(delta: -30), .left)
    }

    func testInvertedNavigationMovesWithTabOrderAndIncludesShelf() {
        XCTAssertEqual(destination(from: .home, direction: .left), .activities)
        XCTAssertEqual(destination(from: .activities, direction: .left), .shelf)
        XCTAssertEqual(destination(from: .shelf, direction: .right), .activities)
        XCTAssertEqual(destination(from: .activities, direction: .right), .home)
        XCTAssertEqual(destination(from: .home, direction: .right), .shelf)
        XCTAssertEqual(destination(from: .shelf, direction: .left), .home)
    }

    func testNonInvertedNavigationReversesPhysicalMapping() {
        XCTAssertEqual(destination(from: .home, direction: .right, isInverted: false), .activities)
        XCTAssertEqual(destination(from: .activities, direction: .right, isInverted: false), .shelf)
        XCTAssertEqual(destination(from: .shelf, direction: .left, isInverted: false), .activities)
        XCTAssertEqual(destination(from: .activities, direction: .left, isInverted: false), .home)
        XCTAssertEqual(destination(from: .home, direction: .left, isInverted: false), .shelf)
        XCTAssertEqual(destination(from: .shelf, direction: .right, isInverted: false), .home)
    }

    func testShelfIsSkippedWhenDisabled() {
        XCTAssertEqual(destination(from: .home, direction: .left, includesShelf: false), .activities)
        XCTAssertEqual(destination(from: .activities, direction: .left, includesShelf: false), .home)
        XCTAssertEqual(destination(from: .activities, direction: .right, includesShelf: false), .home)
        XCTAssertNil(destination(from: .shelf, direction: .right, includesShelf: false))
    }

    private func destination(
        from currentView: NotchViews,
        direction: HorizontalSwipeDirection,
        isInverted: Bool = true,
        includesShelf: Bool = true
    ) -> NotchViews? {
        horizontalSwipeDestination(
            from: currentView,
            direction: direction,
            isInverted: isInverted,
            includesShelf: includesShelf
        )
    }
}

final class TimeActivityManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "TimeActivityManagerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    @MainActor
    func testManagerEnforcesSingleSessionAndReset() {
        var now = Date(timeIntervalSince1970: 3_000)
        let manager = makeManager(now: { now })

        XCTAssertTrue(manager.startStopwatch())
        XCTAssertFalse(manager.startTimer(duration: 60))

        now = now.addingTimeInterval(15)
        XCTAssertEqual(manager.elapsed(at: now), 15, accuracy: 0.001)

        manager.reset()
        XCTAssertNil(manager.snapshot)
        XCTAssertTrue(manager.startTimer(duration: 60))
    }

    @MainActor
    func testExpiredRestoreFinishesAndPlaysSoundOnce() throws {
        let now = Date(timeIntervalSince1970: 4_000)
        let running = try XCTUnwrap(
            TimeActivitySnapshot.timer(duration: 30, startedAt: now.addingTimeInterval(-60))
        )
        defaults.set(try JSONEncoder().encode(running), forKey: "timeActivitySnapshot")

        var soundCount = 0
        let firstManager = makeManager(now: { now }) { soundCount += 1 }
        XCTAssertEqual(firstManager.snapshot?.phase, .finished)
        XCTAssertEqual(soundCount, 1)
        XCTAssertEqual(firstManager.snapshot?.completionSoundPlayed, true)

        let restoredManager = makeManager(now: { now }) { soundCount += 1 }
        XCTAssertEqual(restoredManager.snapshot?.phase, .finished)
        XCTAssertEqual(soundCount, 1)
    }

    @MainActor
    func testPausedSessionPersistsWithoutAdvancing() {
        var now = Date(timeIntervalSince1970: 5_000)
        let manager = makeManager(now: { now })
        XCTAssertTrue(manager.startTimer(duration: 90))

        now = now.addingTimeInterval(20)
        manager.pause()

        now = now.addingTimeInterval(100)
        let restoredManager = makeManager(now: { now })
        XCTAssertEqual(restoredManager.snapshot?.phase, .paused)
        XCTAssertEqual(restoredManager.remaining(at: now), 70, accuracy: 0.001)
    }

    @MainActor
    private func makeManager(
        now: @escaping () -> Date,
        sound: @escaping () -> Void = {}
    ) -> TimeActivityManager {
        TimeActivityManager(
            defaults: defaults,
            now: now,
            observeLifecycle: false,
            playCompletionSound: sound
        )
    }
}
