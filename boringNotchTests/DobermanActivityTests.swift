import SwiftUI
import XCTest
@testable import boringNotch

@MainActor
final class DobermanActivityTests: XCTestCase {
    func testStableMetadataRegistrationAndSizing() throws {
        XCTAssertEqual(DobermanActivity.activityID.rawValue, "builtin.doberman")
        XCTAssertNotNil(ActivityRegistry.shared.activity(for: .doberman))

        let model = DobermanAnimationModel(startsSleeping: false)
        defer { model.cancelAll() }
        let registry = try ActivityRegistry {
            DobermanActivity(model: model)
        }
        let activity = try XCTUnwrap(registry.activity(for: .doberman))

        XCTAssertEqual(activity.metadata.name, "Doberman")
        XCTAssertEqual(activity.metadata.systemImage, "pawprint.fill")
        XCTAssertEqual(
            activity.metadata.summary,
            "A sleeping Doberman companion for the notch."
        )
        XCTAssertEqual(
            activity.livePresentationSizing,
            LiveActivityPresentationSizing(
                fullContentWidth: .fixed(46),
                minimalContentWidth: .fixed(36)
            )
        )
        XCTAssertFalse(activity.supportsConfiguration)
        XCTAssertTrue(activity.isAvailable)
    }

    func testLifecycleReferenceCountingControlsLiveVisibility() {
        let model = DobermanAnimationModel(startsSleeping: false)
        defer { model.cancelAll() }
        let activity = DobermanActivity(model: model)

        XCTAssertEqual(activity.expandedAppearanceCount, 0)
        XCTAssertEqual(activity.livePresentationState, .visible(priority: .low))

        activity.activityDidAppear()
        let firstExpandedGeneration = model.generation
        XCTAssertEqual(activity.expandedAppearanceCount, 1)
        XCTAssertEqual(activity.livePresentationState, .hidden)

        activity.activityDidAppear()
        XCTAssertEqual(activity.expandedAppearanceCount, 2)
        XCTAssertEqual(model.generation, firstExpandedGeneration)
        XCTAssertEqual(activity.livePresentationState, .hidden)

        activity.activityDidDisappear()
        XCTAssertEqual(activity.expandedAppearanceCount, 1)
        XCTAssertEqual(model.generation, firstExpandedGeneration)
        XCTAssertEqual(activity.livePresentationState, .hidden)

        activity.activityDidDisappear()
        XCTAssertEqual(activity.expandedAppearanceCount, 0)
        XCTAssertEqual(model.generation, firstExpandedGeneration + 1)
        XCTAssertEqual(activity.livePresentationState, .visible(priority: .low))
    }

    func testJSXDerivedFrameDefinitionsAreCanonical() {
        XCTAssertEqual(
            DobermanAnimationDefinitions.animation(.walk).frames.map(\.id),
            ["1.1", "1.2", "1.3", "1.4", "2.1", "2.2", "2.3", "2.4"]
        )
        XCTAssertEqual(
            DobermanAnimationDefinitions.animation(.sleepLoop).frames.map(\.id),
            ["5.1", "5.2", "5.3", "5.4", "6.1", "6.2", "6.3", "6.4"]
        )
        XCTAssertEqual(
            DobermanAnimationDefinitions.animation(.layTransition).frames.map(\.id),
            ["3.4", "4.1", "4.2"]
        )
        XCTAssertEqual(
            DobermanAnimationDefinitions.animation(.standFromLayTransition).frames.map(\.id),
            ["4.2", "4.1", "3.4"]
        )
        XCTAssertEqual(DobermanAnimationDefinitions.frameDurationMilliseconds, 100)
        XCTAssertEqual(DobermanAnimationDefinitions.sitHoldMilliseconds, 7000)
    }

    func testDefaultTimelineMatchesJSXOrder() {
        let timeline = DobermanAnimationDefinitions.defaultTimeline

        XCTAssertEqual(
            timeline.map(\.action),
            [
                .walk,
                .layTransition,
                .layHold,
                .layLookAround,
                .lay,
                .sleepLoop,
                .standFromLayTransition,
                .walk,
                .sitTransition,
                .sitHold,
                .sitLookAround,
                .sitTransition,
                .walk
            ]
        )
        XCTAssertEqual(timeline[0].moveTo, .percent(25))
        XCTAssertEqual(timeline[5].holdMilliseconds, 10000)
        XCTAssertEqual(timeline[7].moveTo, .percent(75))
        XCTAssertEqual(timeline[12].moveTo, .exit)
    }

    func testMovementMathMatchesJSXHelpers() {
        let spriteWidth = DobermanAnimationDefinitions.frameWidth
            * DobermanAnimationDefinitions.defaultScale

        XCTAssertEqual(DobermanAnimationDefinitions.startX(spriteWidth: spriteWidth), -132)
        XCTAssertEqual(
            DobermanAnimationDefinitions.targetX(
                for: .percent(25),
                stageWidth: 640,
                spriteWidth: spriteWidth,
                currentX: 0
            ),
            100
        )
        XCTAssertEqual(
            DobermanAnimationDefinitions.targetX(
                for: .exit,
                stageWidth: 640,
                spriteWidth: spriteWidth,
                currentX: 0
            ),
            664
        )
        XCTAssertEqual(DobermanAnimationDefinitions.movementDurationMilliseconds(for: 100), 3500)
        XCTAssertEqual(DobermanAnimationDefinitions.movementDurationMilliseconds(for: 500), 3500)
        XCTAssertEqual(DobermanAnimationDefinitions.movementDurationMilliseconds(for: 2000), 9000)
    }

    func testCloseNormalizationUsesOnlyJSXDerivedTransitions() {
        XCTAssertEqual(
            DobermanAnimationDefinitions.closeSequence(from: .sleeping),
            []
        )
        XCTAssertEqual(
            DobermanAnimationDefinitions.closeSequence(from: .laying),
            []
        )
        XCTAssertEqual(
            DobermanAnimationDefinitions.closeSequence(from: .standing),
            [.layTransition]
        )
        XCTAssertEqual(
            DobermanAnimationDefinitions.closeSequence(from: .walking),
            [.layTransition]
        )
        XCTAssertEqual(
            DobermanAnimationDefinitions.closeSequence(from: .sitting),
            [.standTransition, .layTransition]
        )
    }

    func testViewsShareInjectedAnimationModel() {
        let model = DobermanAnimationModel(startsSleeping: false)
        defer { model.cancelAll() }

        let expanded = DobermanExpandedActivityView(model: model)
        let live = DobermanLivePresentationView(model: model)

        XCTAssertTrue(expanded.model === model)
        XCTAssertTrue(live.model === model)
    }
}
