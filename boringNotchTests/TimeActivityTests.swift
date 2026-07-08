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

    func testInvertedNavigationMovesWithTabOrderAndIncludesCalendarAndShelf() {
        XCTAssertEqual(destination(from: .home, direction: .left), .activity(.calendar))
        XCTAssertEqual(destination(from: .activity(.calendar), direction: .left), .activities)
        XCTAssertEqual(destination(from: .activities, direction: .left), .shelf)
        XCTAssertEqual(destination(from: .shelf, direction: .right), .activities)
        XCTAssertEqual(destination(from: .activities, direction: .right), .activity(.calendar))
        XCTAssertEqual(destination(from: .activity(.calendar), direction: .right), .home)
        XCTAssertEqual(destination(from: .home, direction: .right), .shelf)
        XCTAssertEqual(destination(from: .shelf, direction: .left), .home)
    }

    func testNonInvertedNavigationReversesPhysicalMapping() {
        XCTAssertEqual(destination(from: .home, direction: .right, isInverted: false), .activity(.calendar))
        XCTAssertEqual(destination(from: .activity(.calendar), direction: .right, isInverted: false), .activities)
        XCTAssertEqual(destination(from: .activities, direction: .right, isInverted: false), .shelf)
        XCTAssertEqual(destination(from: .shelf, direction: .left, isInverted: false), .activities)
        XCTAssertEqual(destination(from: .activities, direction: .left, isInverted: false), .activity(.calendar))
        XCTAssertEqual(destination(from: .activity(.calendar), direction: .left, isInverted: false), .home)
        XCTAssertEqual(destination(from: .home, direction: .left, isInverted: false), .shelf)
        XCTAssertEqual(destination(from: .shelf, direction: .right, isInverted: false), .home)
    }

    func testShelfIsSkippedWhenDisabled() {
        XCTAssertEqual(destination(from: .home, direction: .left, includesShelf: false), .activity(.calendar))
        XCTAssertEqual(destination(from: .activity(.calendar), direction: .left, includesShelf: false), .activities)
        XCTAssertEqual(destination(from: .activities, direction: .left, includesShelf: false), .home)
        XCTAssertEqual(destination(from: .activities, direction: .right, includesShelf: false), .activity(.calendar))
        XCTAssertNil(destination(from: .shelf, direction: .right, includesShelf: false))
    }

    func testCalendarIsSkippedWhenDisabled() {
        XCTAssertEqual(destination(from: .home, direction: .left, availableActivityIDs: []), .activities)
        XCTAssertEqual(destination(from: .activities, direction: .right, availableActivityIDs: []), .home)
        XCTAssertNil(destination(from: .activity(.calendar), direction: .left, availableActivityIDs: []))
    }

    func testVisibleNotchViewOrderForFeatureCombinations() {
        XCTAssertEqual(
            visibleNotchViews(availableActivityIDs: [.calendar], includesShelf: true),
            [.home, .activity(.calendar), .activities, .shelf]
        )
        XCTAssertEqual(
            visibleNotchViews(availableActivityIDs: [], includesShelf: true),
            [.home, .activities, .shelf]
        )
        XCTAssertEqual(
            visibleNotchViews(availableActivityIDs: [.calendar], includesShelf: false),
            [.home, .activity(.calendar), .activities]
        )
        XCTAssertEqual(
            visibleNotchViews(availableActivityIDs: [], includesShelf: false),
            [.home, .activities]
        )
    }

    func testHiddenCurrentPageFallsBackToHome() {
        XCTAssertEqual(
            resolvedNotchView(
                .activity(.calendar),
                availableActivityIDs: [],
                includesShelf: true
            ),
            .home
        )
        XCTAssertEqual(
            resolvedNotchView(
                .activity(.calendar),
                availableActivityIDs: [.calendar],
                includesShelf: true
            ),
            .activity(.calendar)
        )
    }

    private func destination(
        from currentView: NotchViews,
        direction: HorizontalSwipeDirection,
        isInverted: Bool = true,
        availableActivityIDs: [ActivityID] = [.calendar],
        includesShelf: Bool = true
    ) -> NotchViews? {
        horizontalSwipeDestination(
            from: currentView,
            direction: direction,
            isInverted: isInverted,
            availableActivityIDs: availableActivityIDs,
            includesShelf: includesShelf
        )
    }
}

final class CalendarMonthLayoutTests: XCTestCase {
    func testLeapYearMonthProducesFortyTwoCellsAndTwentyNineCurrentMonthDays() throws {
        let calendar = makeCalendar(firstWeekday: 1)
        let february = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 2, day: 15)))

        let days = CalendarMonthLayout.days(containing: february, calendar: calendar)

        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(days.filter(\.isInDisplayedMonth).count, 29)
        assertDate(days.first?.date, year: 2024, month: 1, day: 28, calendar: calendar)
        assertDate(days.last?.date, year: 2024, month: 3, day: 9, calendar: calendar)
    }

    func testGridHonorsCalendarFirstWeekday() throws {
        let calendar = makeCalendar(firstWeekday: 2)
        let february = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 2, day: 15)))

        let days = CalendarMonthLayout.days(containing: february, calendar: calendar)

        assertDate(days.first?.date, year: 2024, month: 1, day: 29, calendar: calendar)
        XCTAssertEqual(CalendarMonthLayout.weekdaySymbols(calendar: calendar).count, 7)
    }

    func testSixWeekBoundaryIncludesAdjacentMonthDays() throws {
        let calendar = makeCalendar(firstWeekday: 1)
        let august = try XCTUnwrap(calendar.date(from: DateComponents(year: 2020, month: 8, day: 15)))

        let days = CalendarMonthLayout.days(containing: august, calendar: calendar)

        assertDate(days.first?.date, year: 2020, month: 7, day: 26, calendar: calendar)
        assertDate(days.last?.date, year: 2020, month: 9, day: 5, calendar: calendar)
    }

    func testMovingMonthPreservesAndClampsDayNumber() throws {
        let calendar = makeCalendar(firstWeekday: 1)
        let january31 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 1, day: 31)))
        let february = try XCTUnwrap(CalendarMonthLayout.movingMonth(from: january31, by: 1, calendar: calendar))
        let march = try XCTUnwrap(CalendarMonthLayout.movingMonth(from: february, by: 1, calendar: calendar))

        assertDate(february, year: 2024, month: 2, day: 29, calendar: calendar)
        assertDate(march, year: 2024, month: 3, day: 29, calendar: calendar)
    }

    private func makeCalendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func assertDate(
        _ date: Date?,
        year: Int,
        month: Int,
        day: Int,
        calendar: Calendar,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let date else {
            XCTFail("Expected date", file: file, line: line)
            return
        }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(components.year, year, file: file, line: line)
        XCTAssertEqual(components.month, month, file: file, line: line)
        XCTAssertEqual(components.day, day, file: file, line: line)
    }
}

final class OpenNotchHeightTests: XCTestCase {
    func testOpenNotchHeightUsesBaseAndMaximumBounds() {
        XCTAssertEqual(clampedOpenNotchHeight(openNotchSize.height - 20), openNotchSize.height)
        XCTAssertEqual(clampedOpenNotchHeight(calendarOpenNotchHeight), calendarOpenNotchHeight)
        XCTAssertEqual(clampedOpenNotchHeight(maximumOpenNotchHeight + 20), maximumOpenNotchHeight)
        XCTAssertEqual(notchWindowHeight(for: openNotchSize.height), windowSize.height)
        XCTAssertEqual(
            notchWindowHeight(for: calendarOpenNotchHeight),
            calendarOpenNotchHeight + shadowPadding
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
