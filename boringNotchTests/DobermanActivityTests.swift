import Defaults
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
        XCTAssertTrue(activity.supportsConfiguration)
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
        XCTAssertEqual(
            DobermanAnimationDefinitions.visibleX(
                for: -100,
                stageWidth: 640,
                spriteWidth: spriteWidth
            ),
            90
        )
        XCTAssertEqual(
            DobermanAnimationDefinitions.visibleX(
                for: 700,
                stageWidth: 640,
                spriteWidth: spriteWidth
            ),
            430
        )
        XCTAssertEqual(DobermanAnimationDefinitions.worldTravelMultiplier, 2.046)
    }

    func testParallaxAlwaysRendersLeftCenterAndRightTiles() {
        XCTAssertEqual(DobermanParallaxLayer.tileCount(viewportWidth: 100, tileWidth: 500), 3)
        XCTAssertEqual(DobermanParallaxLayer.tileCount(viewportWidth: 1_500, tileWidth: 500), 5)
        XCTAssertEqual(DobermanParallaxLayer.wrappedOffset(for: 12_345, tileWidth: 500), 345)
        XCTAssertEqual(DobermanParallaxLayer.wrappedOffset(for: -25, tileWidth: 500), 475)
    }

    func testScenePlateRemainsVisibleUntilFullyOutsideViewport() {
        let halfWidth = DobermanScenePlateView.size.width / 2

        XCTAssertTrue(DobermanScenePlateView.isWithinViewport(centerX: -halfWidth, viewportWidth: 640))
        XCTAssertFalse(DobermanScenePlateView.isWithinViewport(centerX: -halfWidth - 0.1, viewportWidth: 640))
        XCTAssertTrue(DobermanScenePlateView.isWithinViewport(centerX: 640 + halfWidth, viewportWidth: 640))
        XCTAssertFalse(DobermanScenePlateView.isWithinViewport(centerX: 640 + halfWidth + 0.1, viewportWidth: 640))
    }

    func testScenePlateUsesDoubledOffscreenDistanceBeforeRetiring() {
        let doubledEdgeDistance = DobermanScenePlateView.size.width

        XCTAssertFalse(DobermanScenePlateView.isSafelyOffscreen(centerX: -doubledEdgeDistance, viewportWidth: 640))
        XCTAssertTrue(DobermanScenePlateView.isSafelyOffscreen(centerX: -doubledEdgeDistance - 0.1, viewportWidth: 640))
        XCTAssertFalse(DobermanScenePlateView.isSafelyOffscreen(centerX: 640 + doubledEdgeDistance, viewportWidth: 640))
        XCTAssertTrue(DobermanScenePlateView.isSafelyOffscreen(centerX: 640 + doubledEdgeDistance + 0.1, viewportWidth: 640))
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
        let needs = makeNeedsModel()
        let controller = DobermanBehaviorController(animationModel: model, needsModel: needs)

        let expanded = DobermanExpandedActivityView(
            model: model,
            needsModel: needs,
            behaviorController: controller
        )
        let live = DobermanLivePresentationView(model: model)

        XCTAssertTrue(expanded.model === model)
        XCTAssertTrue(expanded.needsModel === needs)
        XCTAssertTrue(expanded.behaviorController === controller)
        XCTAssertTrue(live.model === model)
    }

    func testNeedsDefaultValuesAndPersistenceRestoration() {
        withVirtualPetNeedsEnabled(true) {
            var currentDate = Date(timeIntervalSince1970: 1_000)
            let defaults = makeDefaultsSuite()
            let needs = DobermanNeedsModel(
                defaults: defaults,
                now: { currentDate },
                observesSettings: false
            )

            XCTAssertEqual(needs.hunger, 100)
            XCTAssertEqual(needs.thirst, 100)
            XCTAssertEqual(needs.energy, 100)

            currentDate = Date(timeIntervalSince1970: 2_000)
            needs.setNeeds(hunger: 64, thirst: 52, energy: 41, at: currentDate)

            let restored = DobermanNeedsModel(
                defaults: defaults,
                now: { currentDate },
                observesSettings: false
            )

            XCTAssertEqual(restored.hunger, 64)
            XCTAssertEqual(restored.thirst, 52)
            XCTAssertEqual(restored.energy, 41)
            XCTAssertEqual(restored.lastUpdatedAt, currentDate)
        }
    }

    func testNeedsElapsedDecayRecoveryAndClamping() {
        withVirtualPetNeedsEnabled(true) {
            var currentDate = Date(timeIntervalSince1970: 0)
            let needs = DobermanNeedsModel(
                defaults: makeDefaultsSuite(),
                now: { currentDate },
                observesSettings: false
            )

            needs.setNeeds(hunger: 50, thirst: 50, energy: 50, at: currentDate)

            currentDate = Date(timeIntervalSince1970: 3600)
            needs.reconcile(mode: .awake)
            XCTAssertEqual(needs.hunger, 46)
            XCTAssertEqual(needs.thirst, 44)
            XCTAssertEqual(needs.energy, 42)

            currentDate = Date(timeIntervalSince1970: 7200)
            needs.reconcile(mode: .sleeping)
            XCTAssertEqual(needs.hunger, 42)
            XCTAssertEqual(needs.thirst, 38)
            XCTAssertEqual(needs.energy, 60)

            currentDate = Date(timeIntervalSince1970: 72_000)
            needs.reconcile(mode: .closedSleeping)
            XCTAssertEqual(needs.hunger, 0)
            XCTAssertEqual(needs.thirst, 0)
            XCTAssertEqual(needs.energy, 100)
        }
    }

    func testDisabledNeedsPreserveValuesAndAdvanceTimestamp() {
        withVirtualPetNeedsEnabled(false) {
            var currentDate = Date(timeIntervalSince1970: 0)
            let needs = DobermanNeedsModel(
                defaults: makeDefaultsSuite(),
                now: { currentDate },
                observesSettings: false
            )
            needs.setNeeds(hunger: 25, thirst: 35, energy: 45, at: currentDate)

            currentDate = Date(timeIntervalSince1970: 24 * 3600)
            needs.reconcile(mode: .awake)
            needs.feed()
            needs.giveWater()

            XCTAssertFalse(needs.isEnabled)
            XCTAssertEqual(needs.hunger, 25)
            XCTAssertEqual(needs.thirst, 35)
            XCTAssertEqual(needs.energy, 45)
            XCTAssertEqual(needs.lastUpdatedAt, currentDate)
        }
    }

    func testBehaviorWeightsPreventImmediateRepeatAndRespectNeeds() {
        let lowEnergyActions = DobermanBehaviorController.weightedActions(
            needs: DobermanNeedLevels(hunger: 100, thirst: 100, energy: 10, isEnabled: true),
            pose: .standing,
            lastAction: .walk
        )
        let lowEnergyWeights = Dictionary(
            uniqueKeysWithValues: lowEnergyActions.map { ($0.action, $0.weight) }
        )

        XCTAssertNil(lowEnergyWeights[.walk])
        XCTAssertGreaterThan(lowEnergyWeights[.sleep] ?? 0, lowEnergyWeights[.excited] ?? 0)

        let highEnergyActions = DobermanBehaviorController.weightedActions(
            needs: DobermanNeedLevels(hunger: 100, thirst: 100, energy: 95, isEnabled: true),
            pose: .standing,
            lastAction: nil
        )
        let highEnergyWeights = Dictionary(
            uniqueKeysWithValues: highEnergyActions.map { ($0.action, $0.weight) }
        )

        XCTAssertGreaterThan(highEnergyWeights[.walk] ?? 0, highEnergyWeights[.sleep] ?? 0)
        XCTAssertGreaterThan(highEnergyWeights[.excited] ?? 0, 0)
    }

    func testBehaviorWeightsPreferFoodWaterNeedsAndAvoidImmediateWakeAfterSleep() {
        let hungryThirstyActions = DobermanBehaviorController.weightedActions(
            needs: DobermanNeedLevels(hunger: 5, thirst: 8, energy: 80, isEnabled: true),
            pose: .sitting,
            lastAction: nil
        )
        let hungryThirstyWeights = Dictionary(
            uniqueKeysWithValues: hungryThirstyActions.map { ($0.action, $0.weight) }
        )

        XCTAssertGreaterThan(hungryThirstyWeights[.eat] ?? 0, hungryThirstyWeights[.scratch] ?? 0)
        XCTAssertGreaterThan(hungryThirstyWeights[.drink] ?? 0, hungryThirstyWeights[.scratch] ?? 0)

        let afterSleepActions = DobermanBehaviorController.weightedActions(
            needs: DobermanNeedLevels(hunger: 100, thirst: 100, energy: 100, isEnabled: true),
            pose: .sleeping,
            lastAction: .sleep
        )
        let afterSleepActionNames = Set(afterSleepActions.map(\.action))

        XCTAssertFalse(afterSleepActionNames.contains(.walk))
        XCTAssertFalse(afterSleepActionNames.contains(.standFromLaying))
        XCTAssertFalse(afterSleepActionNames.contains(.excited))
    }

    func testWeightedSelectionUsesStableOrder() {
        let actions = [
            DobermanWeightedBehaviorAction(action: .sleep, weight: 1),
            DobermanWeightedBehaviorAction(action: .walk, weight: 3)
        ]

        XCTAssertEqual(
            DobermanBehaviorController.selectWeightedAction(from: actions, randomValue: 0),
            .sleep
        )
        XCTAssertEqual(
            DobermanBehaviorController.selectWeightedAction(from: actions, randomValue: 0.4),
            .walk
        )
    }

    func testPlaceholderBehaviorMappingsAreCentralized() throws {
        let eat = try XCTUnwrap(DobermanPlaceholderBehaviorMappings.mapping(for: .eat))
        XCTAssertEqual(eat.requiredPose, .sitting)
        XCTAssertEqual(eat.execution, .animations([.sitHold]))

        let drink = try XCTUnwrap(DobermanPlaceholderBehaviorMappings.mapping(for: .drink))
        XCTAssertEqual(drink.requiredPose, .laying)
        XCTAssertEqual(drink.execution, .animations([.layHold]))

        let excited = try XCTUnwrap(DobermanPlaceholderBehaviorMappings.mapping(for: .excited))
        XCTAssertEqual(excited.requiredPose, .standing)
        XCTAssertEqual(excited.execution, .activeWalk)
    }

    func testLifecycleReferenceCountingUsesBehaviorControllerGeneration() {
        let model = DobermanAnimationModel(timingScale: 0, startsSleeping: false)
        defer { model.cancelAll() }
        let needs = makeNeedsModel()
        let controller = DobermanBehaviorController(animationModel: model, needsModel: needs)
        let activity = DobermanActivity(
            model: model,
            needsModel: needs,
            behaviorController: controller
        )

        activity.activityDidAppear()
        let firstBehaviorGeneration = controller.generation
        let firstAnimationGeneration = model.generation

        activity.activityDidAppear()
        XCTAssertEqual(controller.generation, firstBehaviorGeneration)
        XCTAssertEqual(model.generation, firstAnimationGeneration)

        activity.activityDidDisappear()
        XCTAssertEqual(controller.generation, firstBehaviorGeneration)
        XCTAssertEqual(model.generation, firstAnimationGeneration)

        activity.activityDidDisappear()
        XCTAssertEqual(controller.generation, firstBehaviorGeneration + 1)
        XCTAssertEqual(model.generation, firstAnimationGeneration + 1)
    }

    func testFeedAndWaterInterruptAmbientAndIncreaseNeeds() async {
        await withVirtualPetNeedsEnabled(true) {
            let model = DobermanAnimationModel(timingScale: 0, startsSleeping: false)
            defer { model.cancelAll() }
            let fixedDate = Date(timeIntervalSince1970: 0)
            let needs = makeNeedsModel(now: { fixedDate })
            needs.setNeeds(hunger: 20, thirst: 20, energy: 80)
            let controller = DobermanBehaviorController(
                animationModel: model,
                needsModel: needs,
                randomDouble: { 0 },
                randomPercent: { 50 }
            )

            controller.transitionToExpanded()
            let expandedGeneration = controller.generation
            controller.feed()
            XCTAssertEqual(controller.generation, expandedGeneration + 1)
            XCTAssertEqual(controller.currentAction, .eat)

            for _ in 0..<20 where needs.hunger <= 20 {
                await Task.yield()
            }
            XCTAssertGreaterThan(needs.hunger, 20)

            controller.giveWater()
            XCTAssertEqual(controller.currentAction, .drink)
            for _ in 0..<20 where needs.thirst <= 20 {
                await Task.yield()
            }
            XCTAssertGreaterThan(needs.thirst, 20)

            controller.transitionToClosed()
        }
    }

    private func makeNeedsModel(
        enabled: Bool = true,
        now: @escaping () -> Date = Date.init
    ) -> DobermanNeedsModel {
        withVirtualPetNeedsEnabled(enabled) {
            DobermanNeedsModel(
                defaults: makeDefaultsSuite(),
                now: now,
                observesSettings: false
            )
        }
    }

    private func makeDefaultsSuite(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> UserDefaults {
        let suiteName = "DobermanActivityTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create defaults suite", file: file, line: line)
            return .standard
        }

        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @discardableResult
    private func withVirtualPetNeedsEnabled<T>(
        _ isEnabled: Bool,
        _ body: () -> T
    ) -> T {
        let previousValue = Defaults[.dobermanVirtualPetNeedsEnabled]
        Defaults[.dobermanVirtualPetNeedsEnabled] = isEnabled
        defer { Defaults[.dobermanVirtualPetNeedsEnabled] = previousValue }
        return body()
    }

    @discardableResult
    private func withVirtualPetNeedsEnabled<T>(
        _ isEnabled: Bool,
        _ body: () async -> T
    ) async -> T {
        let previousValue = Defaults[.dobermanVirtualPetNeedsEnabled]
        Defaults[.dobermanVirtualPetNeedsEnabled] = isEnabled
        defer { Defaults[.dobermanVirtualPetNeedsEnabled] = previousValue }
        return await body()
    }
}
