import Combine
import Defaults
import Foundation
import SwiftUI

extension ActivityID {
    static let doberman = ActivityID("builtin.doberman")
}

private let dobermanSceneContentHeight: CGFloat = 240
private let dobermanOpenNotchChromeReserve: CGFloat = 70
private let dobermanOpenNotchHeightPadding: CGFloat = 26
private let dobermanExpandedBottomMargin: CGFloat = 40
private let dobermanGroundWorldMovementRatio: CGFloat = 1

struct DobermanSceneLayerDefinition: Identifiable, Equatable, Sendable {
    enum Content: Equatable, Sendable {
        case fixed(imageName: String, fillsViewport: Bool)
        case tiled(imageNames: [String], seedSalt: UInt64)
        case drifting(imageName: String, pointsPerSecond: CGFloat)
    }

    let id: String
    let content: Content
    let worldMovementRatio: CGFloat
}

indirect enum DobermanSceneLayerNode: Equatable, Sendable {
    case layer(DobermanSceneLayerDefinition)
    case group(id: String, children: [DobermanSceneLayerNode])

    var flattenedLayers: [DobermanSceneLayerDefinition] {
        switch self {
        case .layer(let layer):
            [layer]
        case .group(_, let children):
            children.flatMap(\.flattenedLayers)
        }
    }
}

struct DobermanSceneDefinition: Equatable, Sendable {
    static let sourceSize = CGSize(width: 300, height: 120)
    static let displayScale: CGFloat = 2
    static let displaySize = CGSize(
        width: sourceSize.width * displayScale,
        height: sourceSize.height * displayScale
    )

    let id: String
    let layers: [DobermanSceneLayerNode]

    var flattenedLayers: [DobermanSceneLayerDefinition] {
        layers.flatMap(\.flattenedLayers)
    }

    static let defaultNoon = DobermanSceneDefinition(
        id: "default-noon",
        layers: [
            .layer(
                DobermanSceneLayerDefinition(
                    id: "1-sky",
                    content: .fixed(
                        imageName: "doberman-default-noon-sky",
                        fillsViewport: true
                    ),
                    worldMovementRatio: 0
                )
            ),
            .layer(
                DobermanSceneLayerDefinition(
                    id: "2-sun",
                    content: .fixed(
                        imageName: "doberman-default-noon-sun",
                        fillsViewport: false
                    ),
                    worldMovementRatio: 0
                )
            ),
            .group(
                id: "3-clouds",
                children: [
                    .layer(
                        DobermanSceneLayerDefinition(
                            id: "3-clouds-far",
                            content: .drifting(
                                imageName: "doberman-default-noon-clouds-far",
                                pointsPerSecond: 4
                            ),
                            worldMovementRatio: 0
                        )
                    ),
                    .layer(
                        DobermanSceneLayerDefinition(
                            id: "3-clouds-near",
                            content: .drifting(
                                imageName: "doberman-default-noon-clouds-near",
                                pointsPerSecond: 8
                            ),
                            worldMovementRatio: 0
                        )
                    )
                ]
            ),
            .group(
                id: "4-background",
                children: [
                    .layer(
                        DobermanSceneLayerDefinition(
                            id: "4-background-strip",
                            content: .tiled(
                                imageNames: [
                                    "doberman-default-noon-background-city",
                                    "doberman-default-noon-background-mountains",
                                    "doberman-default-noon-background-rocky-mountains"
                                ],
                                seedSalt: 0xBACC_600D
                            ),
                            worldMovementRatio: 0.225
                        )
                    )
                ]
            ),
            .layer(
                DobermanSceneLayerDefinition(
                    id: "5-trees",
                    content: .tiled(
                        imageNames: ["doberman-default-noon-trees"],
                        seedSalt: 0x7EEE_5000
                    ),
                    worldMovementRatio: dobermanGroundWorldMovementRatio
                )
            ),
            .group(
                id: "6-foreground",
                children: [
                    .layer(
                        DobermanSceneLayerDefinition(
                            id: "6-foreground-strip",
                            content: .tiled(
                                imageNames: [
                                    "doberman-default-noon-foreground-1",
                                    "doberman-default-noon-foreground-2",
                                    "doberman-default-noon-foreground-3"
                                ],
                                seedSalt: 0xF0AE_600D
                            ),
                            worldMovementRatio: dobermanGroundWorldMovementRatio
                        )
                    )
                ]
            )
        ]
    )
}

struct DobermanSceneSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let seed: UInt64
    let worldTravel: Double
    let cloudEpoch: Date
    let closedAt: Date
    let dogX: Double
    let dogFacesLeft: Bool
}

@MainActor
final class DobermanSceneSessionController: ObservableObject {
    static let sceneryPersistenceDuration: TimeInterval = 5 * 60
    static let dogPositionPersistenceDuration: TimeInterval = 30
    static let storageKey = "dobermanSceneSnapshot.v1"

    @Published private(set) var seed: UInt64
    @Published private(set) var cloudEpoch: Date
    @Published private(set) var activeTime: DobermanSceneTime = .noon

    private let defaults: UserDefaults
    private let now: () -> Date
    private let seedProvider: () -> UInt64

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        seedProvider: @escaping () -> UInt64 = { UInt64.random(in: .min ... .max) }
    ) {
        self.defaults = defaults
        self.now = now
        self.seedProvider = seedProvider
        let date = now()
        seed = seedProvider()
        cloudEpoch = date
    }

    func beginPresentation(
        model: DobermanAnimationModel,
        selectedTime: DobermanSceneTime,
        usesDynamicTime: Bool
    ) {
        let date = now()
        activeTime = usesDynamicTime ? .resolved(for: date) : selectedTime

        guard let snapshot = storedSnapshot(),
              snapshot.version == DobermanSceneSnapshot.currentVersion
        else {
            startFreshScene(model: model, at: date)
            return
        }

        let elapsed = date.timeIntervalSince(snapshot.closedAt)
        guard elapsed >= 0, elapsed <= Self.sceneryPersistenceDuration else {
            startFreshScene(model: model, at: date)
            return
        }

        seed = snapshot.seed
        // Exclude time spent closed so autonomous cloud drift resumes instead of
        // jumping ahead when the scene is presented again.
        cloudEpoch = snapshot.cloudEpoch.addingTimeInterval(elapsed)
        let restoresDog = elapsed <= Self.dogPositionPersistenceDuration
        model.restoreScenePosition(
            worldTravel: CGFloat(snapshot.worldTravel),
            dogX: restoresDog ? CGFloat(snapshot.dogX) : nil,
            facingDirection: restoresDog
                ? (snapshot.dogFacesLeft ? .left : .right)
                : nil
        )
    }

    func endPresentation(model: DobermanAnimationModel) {
        saveSnapshot(model: model, at: now())
    }

    func checkpoint(model: DobermanAnimationModel) {
        saveSnapshot(model: model, at: now())
    }

    private func saveSnapshot(model: DobermanAnimationModel, at date: Date) {
        let snapshot = DobermanSceneSnapshot(
            version: DobermanSceneSnapshot.currentVersion,
            seed: seed,
            worldTravel: Double(model.worldTravel),
            cloudEpoch: cloudEpoch,
            closedAt: date,
            dogX: Double(model.renderState.x),
            dogFacesLeft: model.renderState.facingDirection == .left
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func storedSnapshot() -> DobermanSceneSnapshot? {
        guard let data = defaults.data(forKey: Self.storageKey) else { return nil }
        return try? JSONDecoder().decode(DobermanSceneSnapshot.self, from: data)
    }

    private func startFreshScene(model: DobermanAnimationModel, at date: Date) {
        seed = seedProvider()
        cloudEpoch = date
        model.restoreScenePosition(worldTravel: 0, dogX: nil, facingDirection: nil)
    }
}

@MainActor
final class DobermanActivity: NotchActivity {
    static let activityID = ActivityID.doberman

    let id = activityID
    let metadata = ActivityMetadata(
        name: String(localized: "Doberman"),
        systemImage: "pawprint.fill",
        tint: .brown,
        // The shared open-notch container also lays out pagination and its rounded bottom edge.
        preferredExpandedHeight: dobermanSceneContentHeight + dobermanOpenNotchChromeReserve,
        summary: String(localized: "A sleeping Doberman companion for the notch.")
    )

    let model: DobermanAnimationModel
    let needsModel: DobermanNeedsModel
    let behaviorController: DobermanBehaviorController
    let sceneSession: DobermanSceneSessionController
    @Published private(set) var expandedAppearanceCount = 0
    private var sceneCheckpointCancellable: AnyCancellable?

    init(
        model: DobermanAnimationModel? = nil,
        needsModel: DobermanNeedsModel? = nil,
        behaviorController: DobermanBehaviorController? = nil,
        sceneSession: DobermanSceneSessionController? = nil
    ) {
        let resolvedModel = model ?? DobermanAnimationModel()
        let resolvedNeedsModel = needsModel ?? DobermanNeedsModel()
        let resolvedSceneSession = sceneSession ?? DobermanSceneSessionController()

        self.model = resolvedModel
        self.needsModel = resolvedNeedsModel
        self.sceneSession = resolvedSceneSession
        self.behaviorController = behaviorController
            ?? DobermanBehaviorController(
                animationModel: resolvedModel,
                needsModel: resolvedNeedsModel
            )
        sceneCheckpointCancellable = resolvedModel.$worldTravel
            .dropFirst()
            .sink { [weak resolvedModel, weak resolvedSceneSession] _ in
                guard let resolvedModel, let resolvedSceneSession else { return }
                resolvedSceneSession.checkpoint(model: resolvedModel)
            }
    }

    var isActive: Bool { true }
    var supportsConfiguration: Bool { true }
    var showsAccessoryInMinimalPresentation: Bool { false }

    var livePresentationState: ActivityLivePresentationState {
        // Expanding the companion does not end its background activity. The
        // host hides the chin while open; eligibility must survive the exit
        // animation so closing never renders music alone first.
        .visible(priority: .low)
    }

    let livePresentationSizing = LiveActivityPresentationSizing(
        fullContentWidth: .fixed(46),
        minimalContentWidth: .fixed(36)
    )

    func makeExpandedView() -> some View {
        DobermanExpandedActivityView(
            model: model,
            needsModel: needsModel,
            behaviorController: behaviorController,
            sceneSession: sceneSession
        )
    }

    func makeLivePresentationView() -> some View {
        DobermanLivePresentationView(model: model)
    }

    func makeMinimalLivePresentationView() -> some View {
        DobermanLivePresentationView(model: model)
    }

    func makeConfigurationView() -> some View {
        DobermanSettingsView(needsModel: needsModel)
    }

    func activityDidAppear() {
        expandedAppearanceCount += 1
        guard expandedAppearanceCount == 1 else { return }
        sceneSession.beginPresentation(
            model: model,
            selectedTime: Defaults[.dobermanSceneTime],
            usesDynamicTime: Defaults[.dobermanDynamicTimeEnabled]
        )
        behaviorController.transitionToExpanded()
    }

    func activityDidDisappear() {
        guard expandedAppearanceCount > 0 else { return }
        expandedAppearanceCount -= 1
        guard expandedAppearanceCount == 0 else { return }
        sceneSession.endPresentation(model: model)
        behaviorController.transitionToClosed()
    }
}

struct DobermanSpriteFrame: Equatable, Sendable {
    let row: Int
    let column: Int

    var id: String {
        "\(row + 1).\(column + 1)"
    }

    init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    init(frameID: String) {
        let parts = frameID.split(separator: ".").compactMap { Int($0) }
        precondition(parts.count == 2, "Invalid Doberman frame id: \(frameID)")
        self.init(row: parts[0] - 1, column: parts[1] - 1)
    }
}

enum DobermanAnimationName: String, Equatable, Sendable {
    case walk
    case eatTransition
    case eatLoop
    case sniffLoop
    case sitTransition
    case sitHold
    case sitLookAround
    case standTransition
    case layTransition
    case layHold
    case layLookAround
    case lay
    case sleepLoop
    case standFromLayTransition
}

enum DobermanCanonicalPose: Equatable, Sendable {
    case standing
    case walking
    case sitting
    case laying
    case sleeping
}

enum DobermanPresentationPhase: Equatable, Sendable {
    case sleeping
    case waking
    case expandedTimeline
    case closing
}

enum DobermanActivityPresentationPhase: Equatable, Sendable {
    case closedSleeping
    case opening
    case waking
    case orienting
    case active
    case closing
}

enum DobermanMovementTarget: Equatable, Sendable {
    case start
    case center
    case exit
    case percent(CGFloat)
}

enum DobermanBehaviorState: Equatable, Sendable {
    case idle, walking, sleeping, eating, drinking, playing, lookingAround, transitioning
}

enum DobermanFoodPlateState: Equatable, Sendable {
    case hidden, full, empty
}

enum DobermanFoodPlateSide: Equatable, Sendable {
    case left, right

    var direction: CGFloat { self == .left ? -1 : 1 }
}

enum DobermanCareFeedbackKind: Equatable, Sendable {
    case food
    case water

    var label: String { self == .food ? "Food" : "Water" }
    var icon: String { self == .food ? "fork.knife" : "drop.fill" }
    var color: Color { self == .food ? .orange : .cyan }
}

struct DobermanCareFeedback: Identifiable, Equatable, Sendable {
    let id = UUID()
    let kind: DobermanCareFeedbackKind
    let amount: Int
}

enum DobermanInterruptibility: Equatable, Sendable {
    case immediate, afterFrame, afterLoop, never
}

struct DobermanAnimationClip: Equatable, Sendable {
    let id: String
    let frames: [DobermanSpriteFrame]
    let frameDuration: TimeInterval
    let loops: Bool
    let interruptibility: DobermanInterruptibility
    let movementSpeed: CGFloat?
}

enum DobermanFacingDirection: Equatable, Sendable {
    case left, right

    var scaleX: CGFloat { self == .left ? -1 : 1 }
}

enum DobermanSceneDestination: Equatable, Sendable {
    case randomIdlePoint, foodBowl, waterBowl, bed, playArea

    var percent: CGFloat {
        switch self {
        case .randomIdlePoint: 50
        case .foodBowl: 18
        case .waterBowl: 82
        case .bed: 12
        case .playArea: 62
        }
    }
}

@MainActor
final class DobermanMovementController: ObservableObject {
    static let horizontalPadding: CGFloat = 12
    static let minimumTravel: CGFloat = 36

    @Published private(set) var currentX: CGFloat
    @Published private(set) var targetX: CGFloat
    @Published private(set) var facingDirection: DobermanFacingDirection = .right
    private(set) var sceneWidth: CGFloat = DobermanAnimationDefinitions.defaultStageWidth

    init(currentX: CGFloat = 0) {
        self.currentX = currentX
        self.targetX = currentX
    }

    func updateSceneWidth(_ width: CGFloat) { sceneWidth = max(0, width) }

    func destinationX(for destination: DobermanSceneDestination, spriteWidth: CGFloat) -> CGFloat {
        let available = max(0, sceneWidth - spriteWidth - Self.horizontalPadding * 2)
        let proposed = Self.horizontalPadding + available * destination.percent / 100
        return min(sceneWidth - spriteWidth - Self.horizontalPadding, max(Self.horizontalPadding, proposed))
    }

    func beginMovement(to x: CGFloat) {
        guard abs(x - currentX) >= Self.minimumTravel else { return }
        targetX = x
        facingDirection = x < currentX ? .left : .right
    }

    func arrive() { currentX = targetX }
}

struct DobermanAnimationDefinition: Equatable, Sendable {
    let frames: [DobermanSpriteFrame]
    let loop: Bool
    let holdMilliseconds: Int?
    let frameDurationMilliseconds: Int

    init(
        frames: [DobermanSpriteFrame],
        loop: Bool = false,
        holdMilliseconds: Int? = nil,
        frameDurationMilliseconds: Int = DobermanAnimationDefinitions.frameDurationMilliseconds
    ) {
        self.frames = frames
        self.loop = loop
        self.holdMilliseconds = holdMilliseconds
        self.frameDurationMilliseconds = frameDurationMilliseconds
    }
}

struct DobermanTimelineStep: Equatable, Sendable {
    let action: DobermanAnimationName
    let moveTo: DobermanMovementTarget?
    let holdMilliseconds: Int?
    let durationMilliseconds: Int?

    init(
        action: DobermanAnimationName,
        moveTo: DobermanMovementTarget? = nil,
        holdMilliseconds: Int? = nil,
        durationMilliseconds: Int? = nil
    ) {
        self.action = action
        self.moveTo = moveTo
        self.holdMilliseconds = holdMilliseconds
        self.durationMilliseconds = durationMilliseconds
    }
}

enum DobermanAnimationDefinitions {
    // Sprite frame IDs use a 1-based "row.column" address in the pet sprite sheet.
    // DobermanSpriteSheetView converts those IDs into crop offsets when rendering.
    static let frameWidth: CGFloat = 40
    static let frameHeight: CGFloat = 30
    static let sheetColumns = 4
    static let sheetRows = 8
    static let frameDurationMilliseconds = 100
    static let sitHoldMilliseconds = 7000
    static let defaultScale: CGFloat = 3
    static let expandedSceneScaleMultiplier: CGFloat = 1
    static let expandedSceneScale = defaultScale * expandedSceneScaleMultiplier
    static let movementStartDelayMilliseconds = 50
    static let walkingBobStepMilliseconds = 180
    static let defaultStageWidth: CGFloat = 640
    static let sceneEdgeInset: CGFloat = 90
    static let worldTravelMultiplier: CGFloat = 2.046
    static let walkingPointsPerSecond: CGFloat = 50

    static let defaultFrame = frame("1.1")

    // Shared transition clips can be reused directly or reversed for the matching stand-up motion.
    private static let sitTransitionFrames = frames("3.1")
    private static let layTransitionFrames = frames("3.4", "4.1", "4.2")
    private static let eatTransitionFrames = frames("7.1", "7.2")
    private static let eatLoopFrames = frames("7.3", "7.4", "8.1", "8.2")

    // Default expanded-scene loop. Each step references an animation defined in animation(_:).
    static let defaultTimeline: [DobermanTimelineStep] = [
        DobermanTimelineStep(action: .walk, moveTo: .percent(25)),
        DobermanTimelineStep(action: .layTransition),
        DobermanTimelineStep(action: .layHold),
        DobermanTimelineStep(action: .layLookAround),
        DobermanTimelineStep(action: .lay),
        DobermanTimelineStep(action: .sleepLoop, holdMilliseconds: 10000),
        DobermanTimelineStep(action: .standFromLayTransition),
        DobermanTimelineStep(action: .walk, moveTo: .percent(75)),
        DobermanTimelineStep(action: .sitTransition),
        DobermanTimelineStep(action: .sitHold),
        DobermanTimelineStep(action: .sitLookAround),
        DobermanTimelineStep(action: .sitTransition),
        DobermanTimelineStep(action: .walk, moveTo: .exit)
    ]

    static func frame(_ frameID: String) -> DobermanSpriteFrame {
        DobermanSpriteFrame(frameID: frameID)
    }

    static func frames(_ frameIDs: String...) -> [DobermanSpriteFrame] {
        frameIDs.map(frame)
    }

    // Add a new animation by adding a case to DobermanAnimationName, mapping its frames here,
    // then updating pose(after:) and whichever timeline or behavior should play it.
    static func animation(_ name: DobermanAnimationName) -> DobermanAnimationDefinition {
        switch name {
        case .walk:
            // Rows 1-2: looping walk cycle used while the dog moves through the scene.
            return DobermanAnimationDefinition(
                frames: frames("1.1", "1.2", "1.3", "1.4", "2.1", "2.2", "2.3", "2.4"),
                loop: true
            )
        case .eatTransition:
            // Rows 7.1-7.2: stopping and lowering the head from the walk.
            return DobermanAnimationDefinition(frames: eatTransitionFrames)
        case .eatLoop:
            // Rows 7.3-8.2: shared eating/drinking loop.
            return DobermanAnimationDefinition(frames: eatLoopFrames, loop: true)
        case .sniffLoop:
            // Reuse the eating/drinking cycle for the autonomous sniff behavior.
            return DobermanAnimationDefinition(
                frames: eatLoopFrames,
                loop: true,
                holdMilliseconds: 1600
            )
        case .sitTransition:
            // Row 3, column 1: stand-to-sit transition.
            return DobermanAnimationDefinition(frames: sitTransitionFrames)
        case .sitHold:
            // Row 3, column 2: sitting idle pose held for a longer pause.
            return DobermanAnimationDefinition(
                frames: frames("3.2"),
                holdMilliseconds: sitHoldMilliseconds
            )
        case .sitLookAround:
            // Row 3, column 3: sitting look-around pose.
            return DobermanAnimationDefinition(
                frames: frames("3.3"),
                holdMilliseconds: sitHoldMilliseconds
            )
        case .standTransition:
            // Reverse of sitTransition: sit-to-stand transition.
            return DobermanAnimationDefinition(frames: Array(sitTransitionFrames.reversed()))
        case .layTransition:
            // Row 3, column 4 through row 4, column 2: stand-to-lay transition.
            return DobermanAnimationDefinition(frames: layTransitionFrames)
        case .layHold:
            // Row 4, column 2: laying idle pose held for a longer pause.
            return DobermanAnimationDefinition(
                frames: frames("4.2"),
                holdMilliseconds: sitHoldMilliseconds
            )
        case .layLookAround:
            // Row 4, column 3: laying look-around pose.
            return DobermanAnimationDefinition(
                frames: frames("4.3"),
                holdMilliseconds: sitHoldMilliseconds
            )
        case .lay:
            // Row 4, column 4: settled laying pose used before sleep.
            return DobermanAnimationDefinition(
                frames: frames("4.4"),
                holdMilliseconds: sitHoldMilliseconds
            )
        case .sleepLoop:
            // Rows 5-6: looping sleep/breathing cycle.
            return DobermanAnimationDefinition(
                frames: frames("5.1", "5.2", "5.3", "5.4", "6.1", "6.2", "6.3", "6.4"),
                loop: true
            )
        case .standFromLayTransition:
            // Reverse of layTransition: lay-to-stand transition.
            return DobermanAnimationDefinition(frames: Array(layTransitionFrames.reversed()))
        }
    }

    static func targetX(
        for target: DobermanMovementTarget,
        stageWidth: CGFloat,
        spriteWidth: CGFloat,
        currentX: CGFloat
    ) -> CGFloat {
        switch target {
        case .start:
            return startX(spriteWidth: spriteWidth)
        case .center:
            return round(stageWidth / 2 - spriteWidth / 2)
        case .exit:
            return round(stageWidth + 24)
        case .percent(let percent):
            let clamped = min(100, max(0, percent))
            return round((stageWidth * clamped) / 100 - spriteWidth / 2)
        }
    }

    static func startX(spriteWidth: CGFloat) -> CGFloat {
        round(-spriteWidth - 12)
    }

    static func movementDurationMilliseconds(for distance: CGFloat) -> Int {
        Int(round(abs(distance) / walkingPointsPerSecond * 1000))
    }

    static func visibleX(
        for proposedX: CGFloat,
        stageWidth: CGFloat,
        spriteWidth: CGFloat
    ) -> CGFloat {
        let minimumX = sceneEdgeInset
        let maximumX = max(minimumX, stageWidth - spriteWidth - sceneEdgeInset)
        return min(maximumX, max(minimumX, proposedX))
    }

    static func closeSequence(from pose: DobermanCanonicalPose) -> [DobermanAnimationName] {
        switch pose {
        case .sleeping, .laying:
            return []
        case .standing, .walking:
            return [.layTransition]
        case .sitting:
            return [.standTransition, .layTransition]
        }
    }

    static func pose(after animationName: DobermanAnimationName) -> DobermanCanonicalPose {
        switch animationName {
        case .walk:
            return .walking
        case .sitTransition, .sitHold, .sitLookAround, .eatTransition, .eatLoop, .sniffLoop:
            return .sitting
        case .standTransition, .standFromLayTransition:
            return .standing
        case .layTransition, .layHold, .layLookAround, .lay:
            return .laying
        case .sleepLoop:
            return .sleeping
        }
    }
}

struct DobermanRenderState: Equatable, Sendable {
    var frame: DobermanSpriteFrame
    var phase: DobermanPresentationPhase
    var pose: DobermanCanonicalPose
    var currentAction: DobermanAnimationName
    var x: CGFloat
    var movementDuration: TimeInterval
    var isWalking: Bool
    var walkBobOffset: CGFloat
    var facingDirection: DobermanFacingDirection

    static func initial() -> DobermanRenderState {
        let sleep = DobermanAnimationDefinitions.animation(.sleepLoop)
        let spriteWidth = DobermanAnimationDefinitions.frameWidth
            * DobermanAnimationDefinitions.defaultScale
        let centerX = DobermanAnimationDefinitions.targetX(
            for: .center,
            stageWidth: DobermanAnimationDefinitions.defaultStageWidth,
            spriteWidth: spriteWidth,
            currentX: 0
        )

        return DobermanRenderState(
            frame: sleep.frames[0],
            phase: .sleeping,
            pose: .sleeping,
            currentAction: .sleepLoop,
            x: centerX,
            movementDuration: 0,
            isWalking: false,
            walkBobOffset: 0,
            facingDirection: .right
        )
    }
}

enum DobermanNeedsElapsedMode: Equatable, Sendable {
    case awake
    case sleeping
    case closedSleeping
}

struct DobermanNeedLevels: Equatable, Sendable {
    var hunger: Double
    var thirst: Double
    var energy: Double
    var isEnabled: Bool

    static let full = DobermanNeedLevels(
        hunger: 100,
        thirst: 100,
        energy: 100,
        isEnabled: true
    )
}

private struct DobermanNeedsPersistenceSnapshot: Codable, Equatable {
    var hunger: Double
    var thirst: Double
    var energy: Double
    var lastUpdatedAt: Date
}

@MainActor
final class DobermanNeedsModel: ObservableObject {
    static let persistenceKey = "dobermanVirtualPetNeedsSnapshot"
    static let hungerDecayPerHour = 4.0
    static let thirstDecayPerHour = 6.0
    static let awakeEnergyDecayPerHour = 8.0
    static let sleepingEnergyRecoveryPerHour = 18.0
    static let closedSleepingEnergyRecoveryPerHour = 12.0

    @Published private(set) var hunger: Double
    @Published private(set) var thirst: Double
    @Published private(set) var energy: Double
    @Published private(set) var isEnabled: Bool

    private(set) var lastUpdatedAt: Date

    var levels: DobermanNeedLevels {
        DobermanNeedLevels(
            hunger: hunger,
            thirst: thirst,
            energy: energy,
            isEnabled: isEnabled
        )
    }

    private let defaults: UserDefaults
    private let nowProvider: () -> Date
    private var settingsObservation: AnyCancellable?

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        observesSettings: Bool = true
    ) {
        self.defaults = defaults
        self.nowProvider = now
        self.isEnabled = Defaults[.dobermanVirtualPetNeedsEnabled]

        if let snapshot = Self.restoreSnapshot(from: defaults) {
            hunger = Self.clamp(snapshot.hunger)
            thirst = Self.clamp(snapshot.thirst)
            energy = Self.clamp(snapshot.energy)
            lastUpdatedAt = snapshot.lastUpdatedAt
        } else {
            hunger = 100
            thirst = 100
            energy = 100
            lastUpdatedAt = now()
        }

        if observesSettings {
            settingsObservation = Defaults.publisher(.dobermanVirtualPetNeedsEnabled)
                .map(\.newValue)
                .removeDuplicates()
                .receive(on: RunLoop.main)
                .sink { [weak self] isEnabled in
                    self?.setNeedsEnabled(isEnabled)
                }
        }
    }

    func reconcile(mode: DobermanNeedsElapsedMode, at date: Date? = nil) {
        let resolvedDate = date ?? nowProvider()
        let elapsedHours = max(0, resolvedDate.timeIntervalSince(lastUpdatedAt)) / 3600
        lastUpdatedAt = resolvedDate

        guard isEnabled else {
            persistSnapshot()
            return
        }

        hunger = Self.clamp(hunger - Self.hungerDecayPerHour * elapsedHours)
        thirst = Self.clamp(thirst - Self.thirstDecayPerHour * elapsedHours)

        switch mode {
        case .awake:
            energy = Self.clamp(energy - Self.awakeEnergyDecayPerHour * elapsedHours)
        case .sleeping:
            energy = Self.clamp(energy + Self.sleepingEnergyRecoveryPerHour * elapsedHours)
        case .closedSleeping:
            energy = Self.clamp(
                energy + Self.closedSleepingEnergyRecoveryPerHour * elapsedHours
            )
        }

        persistSnapshot()
    }

    func feed(amount: Double = 30, at date: Date? = nil) {
        reconcile(mode: .awake, at: date)
        guard isEnabled else { return }
        hunger = Self.clamp(hunger + amount)
        persistSnapshot()
    }

    func giveWater(amount: Double = 35, at date: Date? = nil) {
        reconcile(mode: .awake, at: date)
        guard isEnabled else { return }
        thirst = Self.clamp(thirst + amount)
        persistSnapshot()
    }

    func setNeeds(
        hunger: Double,
        thirst: Double,
        energy: Double,
        at date: Date? = nil
    ) {
        self.hunger = Self.clamp(hunger)
        self.thirst = Self.clamp(thirst)
        self.energy = Self.clamp(energy)
        lastUpdatedAt = date ?? nowProvider()
        persistSnapshot()
    }

    static func clamp(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    private func setNeedsEnabled(_ isEnabled: Bool) {
        guard self.isEnabled != isEnabled else { return }
        self.isEnabled = isEnabled
        lastUpdatedAt = nowProvider()
        persistSnapshot()
    }

    private func persistSnapshot() {
        let snapshot = DobermanNeedsPersistenceSnapshot(
            hunger: hunger,
            thirst: thirst,
            energy: energy,
            lastUpdatedAt: lastUpdatedAt
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.persistenceKey)
    }

    private static func restoreSnapshot(
        from defaults: UserDefaults
    ) -> DobermanNeedsPersistenceSnapshot? {
        guard let data = defaults.data(forKey: persistenceKey) else { return nil }
        return try? JSONDecoder().decode(
            DobermanNeedsPersistenceSnapshot.self,
            from: data
        )
    }
}

enum DobermanBehaviorAction: String, CaseIterable, Equatable, Sendable {
    case walk
    case sit
    case sitLookAround
    case standFromSitting
    case layDown
    case layLookAround
    case sleep
    case standFromLaying
    case eat
    case drink
    case sniff
    case excited
    case scratch
}

struct DobermanWeightedBehaviorAction: Equatable, Sendable {
    var action: DobermanBehaviorAction
    var weight: Double
}

struct DobermanPlaceholderBehaviorMapping: Equatable, Sendable {
    enum Execution: Equatable, Sendable {
        case animations([DobermanAnimationName])
        case activeWalk
    }

    var action: DobermanBehaviorAction
    var requiredPose: DobermanCanonicalPose
    var execution: Execution
    var note: String
}

enum DobermanPlaceholderBehaviorMappings {
    static func mapping(
        for action: DobermanBehaviorAction
    ) -> DobermanPlaceholderBehaviorMapping? {
        switch action {
        case .eat:
            return DobermanPlaceholderBehaviorMapping(
                action: action,
                requiredPose: .standing,
                execution: .animations([.eatTransition, .eatLoop]),
                note: "Uses the shared eating/drinking animation sequence."
            )
        case .drink:
            return DobermanPlaceholderBehaviorMapping(
                action: action,
                requiredPose: .standing,
                execution: .animations([.eatTransition, .eatLoop]),
                note: "Uses the shared eating/drinking animation sequence."
            )
        case .sniff:
            return DobermanPlaceholderBehaviorMapping(
                action: action,
                requiredPose: .standing,
                execution: .animations([.eatTransition, .sniffLoop]),
                note: "Reuses the eating/drinking frames for sniffing."
            )
        case .excited:
            return DobermanPlaceholderBehaviorMapping(
                action: action,
                requiredPose: .standing,
                execution: .activeWalk,
                note: "Placeholder: reuses the active walking frames until excited frames exist."
            )
        case .scratch:
            return DobermanPlaceholderBehaviorMapping(
                action: action,
                requiredPose: .sitting,
                execution: .animations([.sitLookAround]),
                note: "Placeholder: replace with scratching frames when available."
            )
        default:
            return nil
        }
    }
}

@MainActor
final class DobermanBehaviorController: ObservableObject {
    @Published private(set) var currentAction: DobermanBehaviorAction?
    @Published private(set) var isExpanded = false
    @Published private(set) var presentationPhase: DobermanActivityPresentationPhase = .closedSleeping
    @Published private(set) var isInteracting = false
    @Published private(set) var foodPlateState: DobermanFoodPlateState = .hidden
    @Published private(set) var foodPlateSide: DobermanFoodPlateSide = .left
    @Published private(set) var isFoodPlateInScene = false
    @Published private(set) var foodPlateSpawnTravel: CGFloat = 0
    @Published private(set) var waterPlateState: DobermanFoodPlateState = .hidden
    @Published private(set) var waterPlateSide: DobermanFoodPlateSide = .left
    @Published private(set) var isWaterPlateInScene = false
    @Published private(set) var waterPlateSpawnTravel: CGFloat = 0
    @Published private(set) var careFeedback: DobermanCareFeedback?

    private(set) var generation = 0

    private let animationModel: DobermanAnimationModel
    private let needsModel: DobermanNeedsModel
    private let randomDoubleProvider: () -> Double
    private let randomPercentProvider: () -> CGFloat
    private let careInteractionDuration: TimeInterval
    private var behaviorTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var lastAction: DobermanBehaviorAction?

    init(
        animationModel: DobermanAnimationModel,
        needsModel: DobermanNeedsModel,
        randomDouble: @escaping () -> Double = { Double.random(in: 0..<1) },
        randomPercent: @escaping () -> CGFloat = { CGFloat.random(in: 15...85) },
        careInteractionDuration: TimeInterval = 5
    ) {
        self.animationModel = animationModel
        self.needsModel = needsModel
        self.randomDoubleProvider = randomDouble
        self.randomPercentProvider = randomPercent
        self.careInteractionDuration = max(0, careInteractionDuration)
    }

    deinit {
        behaviorTask?.cancel()
        feedbackTask?.cancel()
    }

    func transitionToExpanded() {
        guard !isExpanded else { return }
        isExpanded = true
        presentationPhase = .opening
        needsModel.reconcile(mode: .closedSleeping)

        let behaviorToken = beginBehaviorGeneration()
        let animationToken = animationModel.beginControlledAnimation()
        behaviorTask = Task { @MainActor [weak self] in
            await self?.runExpandedBehavior(
                behaviorToken: behaviorToken,
                animationToken: animationToken
            )
        }
    }

    func transitionToClosed() {
        guard isExpanded || behaviorTask != nil else { return }
        isExpanded = false
        presentationPhase = .closing
        _ = beginBehaviorGeneration()
        currentAction = nil
        isInteracting = false
        foodPlateState = .hidden
        isFoodPlateInScene = false
        waterPlateState = .hidden
        isWaterPlateInScene = false
        feedbackTask?.cancel()
        careFeedback = nil
        needsModel.reconcile(mode: currentNeedsMode)
        animationModel.transitionToClosed()
        presentationPhase = .closedSleeping
    }

    func feed() {
        guard isExpanded, needsModel.isEnabled else { return }
        foodPlateSide = randomDoubleProvider() < 0.5 ? .left : .right
        foodPlateSpawnTravel = animationModel.worldTravel
        foodPlateState = .full
        isFoodPlateInScene = false
        startCareInteraction(.eat) { [weak self] in
            self?.applyCareReward(.food)
        }
    }

    func giveWater() {
        guard isExpanded, needsModel.isEnabled else { return }
        waterPlateSide = randomDoubleProvider() < 0.5 ? .left : .right
        waterPlateSpawnTravel = animationModel.worldTravel
        waterPlateState = .full
        isWaterPlateInScene = false
        startCareInteraction(.drink) { [weak self] in
            self?.applyCareReward(.water)
        }
    }

    private func applyCareReward(_ kind: DobermanCareFeedbackKind) {
        let previousValue = kind == .food ? needsModel.hunger : needsModel.thirst
        if kind == .food {
            needsModel.feed()
        } else {
            needsModel.giveWater()
        }
        let updatedValue = kind == .food ? needsModel.hunger : needsModel.thirst
        let amount = max(0, Int(round(updatedValue - previousValue)))
        showCareFeedback(kind: kind, amount: amount)
    }

    private func showCareFeedback(kind: DobermanCareFeedbackKind, amount: Int) {
        feedbackTask?.cancel()
        let feedback = DobermanCareFeedback(kind: kind, amount: amount)
        careFeedback = feedback
        feedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled, self?.careFeedback?.id == feedback.id else { return }
            self?.careFeedback = nil
        }
    }

    func retireFoodPlate() {
        guard foodPlateState == .empty else { return }
        foodPlateState = .hidden
        isFoodPlateInScene = false
    }

    func retireWaterPlate() {
        guard waterPlateState == .empty else { return }
        waterPlateState = .hidden
        isWaterPlateInScene = false
    }

    static func weightedActions(
        needs: DobermanNeedLevels,
        pose: DobermanCanonicalPose,
        lastAction: DobermanBehaviorAction?
    ) -> [DobermanWeightedBehaviorAction] {
        var weights: [DobermanBehaviorAction: Double] = [:]

        func add(_ action: DobermanBehaviorAction, weight: Double) {
            weights[action, default: 0] += weight
        }

        switch pose {
        case .standing, .walking:
            add(.walk, weight: 18)
            add(.sit, weight: 10)
            add(.layDown, weight: 8)
            add(.excited, weight: 4)
            add(.scratch, weight: 5)
            add(.sniff, weight: 5)
            add(.sleep, weight: 4)
        case .sitting:
            add(.sitLookAround, weight: 12)
            add(.sniff, weight: 5)
            add(.standFromSitting, weight: 7)
            add(.layDown, weight: 8)
            add(.walk, weight: 12)
            add(.scratch, weight: 6)
            add(.sleep, weight: 4)
            add(.excited, weight: 3)
        case .laying:
            add(.layLookAround, weight: 12)
            add(.sleep, weight: 10)
            add(.standFromLaying, weight: 8)
            add(.walk, weight: 10)
            add(.sit, weight: 5)
        case .sleeping:
            add(.sleep, weight: 12)
            add(.layLookAround, weight: 8)
            add(.standFromLaying, weight: 6)
            add(.walk, weight: 8)
        }

        if needs.isEnabled {
            add(.eat, weight: 2)
            add(.drink, weight: 2)

            if needs.energy < 35 {
                weights[.sleep, default: 0] += 35 - needs.energy + 20
                weights[.layDown, default: 0] += 18
                weights[.layLookAround, default: 0] += 12
                weights[.walk] = (weights[.walk] ?? 0) * 0.35
                weights[.excited] = (weights[.excited] ?? 0) * 0.25
            } else if needs.energy > 70 {
                weights[.walk, default: 0] += 18
                weights[.excited, default: 0] += 10
                weights[.sleep] = (weights[.sleep] ?? 0) * 0.45
                weights[.layDown] = (weights[.layDown] ?? 0) * 0.65
            }

            if needs.hunger < 45 {
                weights[.eat, default: 0] += 45 - needs.hunger + 10
            }

            if needs.thirst < 45 {
                weights[.drink, default: 0] += 45 - needs.thirst + 10
            }
        } else {
            weights[.eat] = nil
            weights[.drink] = nil
        }

        if lastAction == .sleep {
            weights[.walk] = nil
            weights[.standFromLaying] = nil
            weights[.excited] = nil
        }

        if let lastAction, weights.count > 1 {
            weights[lastAction] = nil
        }

        let weightedActions: [DobermanWeightedBehaviorAction] =
            DobermanBehaviorAction.allCases.compactMap { action in
                guard let weight = weights[action], weight > 0 else { return nil }
                return DobermanWeightedBehaviorAction(action: action, weight: weight)
            }

        if !weightedActions.isEmpty {
            return weightedActions
        }

        return [
            DobermanWeightedBehaviorAction(action: .layLookAround, weight: 1),
            DobermanWeightedBehaviorAction(action: .sleep, weight: 1)
        ]
    }

    static func selectWeightedAction(
        from actions: [DobermanWeightedBehaviorAction],
        randomValue: Double
    ) -> DobermanBehaviorAction? {
        let totalWeight = actions.reduce(0) { $0 + max(0, $1.weight) }
        guard totalWeight > 0 else { return nil }

        var threshold = min(0.999_999, max(0, randomValue)) * totalWeight
        for action in actions where action.weight > 0 {
            if threshold < action.weight {
                return action.action
            }
            threshold -= action.weight
        }

        return actions.last?.action
    }

    private var currentNeedsMode: DobermanNeedsElapsedMode {
        animationModel.currentPose == .sleeping ? .sleeping : .awake
    }

    private func beginBehaviorGeneration() -> Int {
        generation += 1
        behaviorTask?.cancel()
        behaviorTask = nil
        return generation
    }

    private func runExpandedBehavior(
        behaviorToken: Int,
        animationToken: Int
    ) async {
        do {
            try ensureCurrent(behaviorToken)
            // TODO: Replace this sleeping hold with a subtle ear-twitch or head-lift animation.
            try await animationModel.holdForBehavior(
                milliseconds: 200,
                token: animationToken
            )
            try ensureCurrent(behaviorToken)
            presentationPhase = .waking
            try await animationModel.wakeForExpandedBehavior(token: animationToken)
            try ensureCurrent(behaviorToken)
            presentationPhase = .orienting
            // TODO: Replace this standing hold with a dedicated opening look-around animation.
            try await animationModel.holdForBehavior(
                milliseconds: 350,
                token: animationToken
            )
            try ensureCurrent(behaviorToken)
            presentationPhase = .active
            try await runAmbientLoop(
                behaviorToken: behaviorToken,
                animationToken: animationToken
            )
        } catch {
            clearTransientStateIfCurrent(behaviorToken)
        }
    }

    private func startCareInteraction(
        _ action: DobermanBehaviorAction,
        completion: @escaping @MainActor () -> Void
    ) {
        let behaviorToken = beginBehaviorGeneration()
        let animationToken = animationModel.beginControlledAnimation()
        currentAction = action
        isInteracting = true

        behaviorTask = Task { @MainActor [weak self] in
            await self?.runCareInteraction(
                action,
                behaviorToken: behaviorToken,
                animationToken: animationToken,
                completion: completion
            )
        }
    }

    private func runCareInteraction(
        _ action: DobermanBehaviorAction,
        behaviorToken: Int,
        animationToken: Int,
        completion: @escaping @MainActor () -> Void
    ) async {
        do {
            try ensureCurrent(behaviorToken)
            let destinationPercent: CGFloat
            if action == .eat {
                destinationPercent = animationModel.plateDestinationPercent(side: foodPlateSide)
            } else {
                destinationPercent = animationModel.plateDestinationPercent(side: waterPlateSide)
            }
            try await animationModel.normalizeForBehavior(to: .standing, token: animationToken)
            if action == .eat {
                isFoodPlateInScene = true
            } else {
                isWaterPlateInScene = true
            }
            try await animationModel.walkForBehavior(
                toPercent: destinationPercent,
                token: animationToken
            )
            try ensureCurrent(behaviorToken)
            if action == .eat {
                try await runEatingInteraction(
                    behaviorToken: behaviorToken,
                    animationToken: animationToken
                )
            } else if action == .drink {
                try await runDrinkingInteraction(
                    behaviorToken: behaviorToken,
                    animationToken: animationToken
                )
            } else {
                try await execute(action, behaviorToken: behaviorToken, animationToken: animationToken)
            }
            try ensureCurrent(behaviorToken)
            completion()
            isInteracting = false
            try await runAmbientLoop(
                behaviorToken: behaviorToken,
                animationToken: animationToken
            )
        } catch {
            clearTransientStateIfCurrent(behaviorToken)
        }
    }

    private func runEatingInteraction(
        behaviorToken: Int,
        animationToken: Int
    ) async throws {
        try await animationModel.performBehaviorAnimation(.eatTransition, token: animationToken)
        try ensureCurrent(behaviorToken)

        let emptyPlateTask = Task { @MainActor [weak self] in
            try await Task.sleep(for: .seconds(careInteractionDuration))
            guard let self else { return }
            try self.ensureCurrent(behaviorToken)
            self.foodPlateState = .empty
        }

        defer { emptyPlateTask.cancel() }
        try await animationModel.loopBehaviorAnimation(
            .eatLoop,
            milliseconds: Int(careInteractionDuration * 1000),
            token: animationToken
        )
        try await emptyPlateTask.value
    }

    private func runDrinkingInteraction(
        behaviorToken: Int,
        animationToken: Int
    ) async throws {
        try await animationModel.performBehaviorAnimation(.eatTransition, token: animationToken)
        try ensureCurrent(behaviorToken)

        let emptyPlateTask = Task { @MainActor [weak self] in
            try await Task.sleep(for: .seconds(careInteractionDuration))
            guard let self else { return }
            try self.ensureCurrent(behaviorToken)
            self.waterPlateState = .empty
        }

        defer { emptyPlateTask.cancel() }
        try await animationModel.loopBehaviorAnimation(
            .eatLoop,
            milliseconds: Int(careInteractionDuration * 1000),
            token: animationToken
        )
        try await emptyPlateTask.value
    }

    private func runAmbientLoop(
        behaviorToken: Int,
        animationToken: Int
    ) async throws {
        while true {
            try ensureCurrent(behaviorToken)
            needsModel.reconcile(mode: currentNeedsMode)

            if !Defaults[.dobermanAutonomousBehaviorsEnabled] {
                currentAction = .layLookAround
                try await animationModel.normalizeForBehavior(to: .laying, token: animationToken)
                try await animationModel.performBehaviorAnimation(.layLookAround, token: animationToken)
                continue
            }

            let action = selectNextAction()
            currentAction = action
            lastAction = action

            try await execute(
                action,
                behaviorToken: behaviorToken,
                animationToken: animationToken
            )
        }
    }

    private func selectNextAction() -> DobermanBehaviorAction {
        let actions = Self.weightedActions(
            needs: needsModel.levels,
            pose: animationModel.currentPose,
            lastAction: lastAction
        )

        return Self.selectWeightedAction(
            from: actions,
            randomValue: randomDoubleProvider()
        ) ?? .layLookAround
    }

    private func execute(
        _ action: DobermanBehaviorAction,
        behaviorToken: Int,
        animationToken: Int
    ) async throws {
        try ensureCurrent(behaviorToken)

        switch action {
        case .walk:
            guard Defaults[.dobermanRandomMovementEnabled] else {
                try await animationModel.performBehaviorAnimation(.sitHold, token: animationToken)
                return
            }
            try await animationModel.normalizeForBehavior(to: .standing, token: animationToken)
            try ensureCurrent(behaviorToken)
            try await animationModel.walkForBehavior(
                toPercent: randomPercentProvider(),
                token: animationToken
            )
        case .sit:
            try await animationModel.normalizeForBehavior(to: .sitting, token: animationToken)
        case .sitLookAround:
            try await animationModel.normalizeForBehavior(to: .sitting, token: animationToken)
            try ensureCurrent(behaviorToken)
            try await animationModel.performBehaviorAnimation(
                .sitLookAround,
                token: animationToken
            )
        case .standFromSitting:
            try await animationModel.normalizeForBehavior(to: .standing, token: animationToken)
        case .layDown:
            try await animationModel.normalizeForBehavior(to: .laying, token: animationToken)
        case .layLookAround:
            try await animationModel.normalizeForBehavior(to: .laying, token: animationToken)
            try ensureCurrent(behaviorToken)
            try await animationModel.performBehaviorAnimation(
                .layLookAround,
                token: animationToken
            )
        case .sleep:
            try await animationModel.normalizeForBehavior(to: .laying, token: animationToken)
            try ensureCurrent(behaviorToken)
            try await animationModel.sleepForBehavior(
                milliseconds: randomSleepMilliseconds(),
                token: animationToken
            )
        case .standFromLaying:
            try await animationModel.normalizeForBehavior(to: .standing, token: animationToken)
        case .eat, .drink, .sniff, .excited, .scratch:
            try await executePlaceholder(
                action,
                behaviorToken: behaviorToken,
                animationToken: animationToken
            )
        }
    }

    private func executePlaceholder(
        _ action: DobermanBehaviorAction,
        behaviorToken: Int,
        animationToken: Int
    ) async throws {
        guard let mapping = DobermanPlaceholderBehaviorMappings.mapping(for: action) else {
            return
        }

        try await animationModel.normalizeForBehavior(
            to: mapping.requiredPose,
            token: animationToken
        )
        try ensureCurrent(behaviorToken)

        switch mapping.execution {
        case .animations(let animations):
            for animation in animations {
                try ensureCurrent(behaviorToken)
                try await animationModel.performBehaviorAnimation(animation, token: animationToken)
            }
        case .activeWalk:
            try await animationModel.walkForBehavior(
                toPercent: randomPercentProvider(),
                token: animationToken
            )
        }
    }

    private func randomSleepMilliseconds() -> Int {
        Int(round(6000 + randomDoubleProvider() * 8000))
    }

    private func ensureCurrent(_ token: Int) throws {
        if Task.isCancelled || generation != token || !isExpanded {
            throw CancellationError()
        }
    }

    private func clearTransientStateIfCurrent(_ token: Int) {
        guard generation == token else { return }
        currentAction = nil
        isInteracting = false
    }
}

// Architectural names used by the scene layer; aliases preserve source compatibility.
typealias DobermanSimulation = DobermanBehaviorController
typealias DobermanAnimator = DobermanAnimationModel

@MainActor
final class DobermanAnimationModel: ObservableObject {
    @Published private(set) var renderState: DobermanRenderState
    @Published private(set) var worldTravel: CGFloat = 0

    private(set) var generation = 0
    private var expandedStageWidth = DobermanAnimationDefinitions.defaultStageWidth
    private let timingScale: Double
    private var animationTask: Task<Void, Never>?
    private var preservesRestoredDogPosition = false

    init(timingScale: Double = 1, startsSleeping: Bool = true) {
        self.timingScale = max(0, timingScale)
        renderState = .initial()

        if startsSleeping {
            startSleepLoop()
        }
    }

    deinit {
        animationTask?.cancel()
    }

    func updateExpandedStageWidth(_ width: CGFloat) {
        expandedStageWidth = max(0, width)
        let spriteWidth = DobermanAnimationDefinitions.frameWidth
            * DobermanAnimationDefinitions.defaultScale
        let proposedX = preservesRestoredDogPosition
            ? renderState.x
            : expandedStageWidth / 2 - spriteWidth / 2
        renderState = updatedState(
            x: DobermanAnimationDefinitions.visibleX(
                for: proposedX,
                stageWidth: expandedStageWidth,
                spriteWidth: spriteWidth
            )
        )
    }

    func restoreScenePosition(
        worldTravel: CGFloat,
        dogX: CGFloat?,
        facingDirection: DobermanFacingDirection?
    ) {
        self.worldTravel = worldTravel
        preservesRestoredDogPosition = dogX != nil
        renderState = updatedState(
            x: dogX ?? renderState.x,
            movementDuration: 0,
            isWalking: false,
            walkBobOffset: 0,
            facingDirection: facingDirection ?? renderState.facingDirection
        )
    }

    func plateDestinationPercent(side: DobermanFoodPlateSide) -> CGFloat {
        let spriteWidth = DobermanAnimationDefinitions.frameWidth
            * DobermanAnimationDefinitions.defaultScale
        let grassDepth = DobermanSceneView.grassDepth
        let dogTravel = expandedStageWidth
            / (DobermanAnimationDefinitions.worldTravelMultiplier * grassDepth)
        let targetX = renderState.x + side.direction * dogTravel
        return min(100, max(0, (targetX + spriteWidth / 2) / expandedStageWidth * 100))
    }

    var currentPose: DobermanCanonicalPose {
        renderState.pose
    }

    func transitionToExpanded() {
        let token = beginControlledAnimation()
        animationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.wakeForExpandedBehavior(token: token)
            } catch {
                return
            }
        }
    }

    func transitionToClosed() {
        generation += 1
        let token = generation
        animationTask?.cancel()
        animationTask = Task { @MainActor [weak self] in
            await self?.runClosed(token: token)
        }
    }

    func cancelAll() {
        generation += 1
        animationTask?.cancel()
        animationTask = nil
    }

    @discardableResult
    func beginControlledAnimation() -> Int {
        generation += 1
        animationTask?.cancel()
        animationTask = nil
        return generation
    }

    func isCurrentGeneration(_ token: Int) -> Bool {
        generation == token
    }

    func wakeForExpandedBehavior(token: Int) async throws {
        try ensureCurrent(token)
        setMovementDuration(0)

        switch renderState.pose {
        case .sleeping, .laying:
            try await playAnimation(.standFromLayTransition, phase: .waking, token: token)
        case .sitting:
            try await playAnimation(.standTransition, phase: .waking, token: token)
        case .standing:
            renderState = updatedState(
                phase: .waking,
                pose: .standing,
                movementDuration: 0,
                isWalking: false,
                walkBobOffset: 0
            )
        case .walking:
            renderState = updatedState(
                phase: .waking,
                pose: .standing,
                movementDuration: 0,
                isWalking: false,
                walkBobOffset: 0
            )
        }
    }

    func normalizeForBehavior(
        to pose: DobermanCanonicalPose,
        token: Int
    ) async throws {
        try ensureCurrent(token)
        setMovementDuration(0)

        switch pose {
        case .standing, .walking:
            switch renderState.pose {
            case .sleeping, .laying:
                try await playAnimation(
                    .standFromLayTransition,
                    phase: .expandedTimeline,
                    token: token
                )
            case .sitting:
                try await playAnimation(
                    .standTransition,
                    phase: .expandedTimeline,
                    token: token
                )
            case .standing:
                renderState = updatedState(
                    phase: .expandedTimeline,
                    pose: .standing,
                    movementDuration: 0,
                    isWalking: false,
                    walkBobOffset: 0
                )
            case .walking:
                renderState = updatedState(
                    phase: .expandedTimeline,
                    pose: .standing,
                    movementDuration: 0,
                    isWalking: false,
                    walkBobOffset: 0
                )
            }
        case .sitting:
            if renderState.pose != .sitting {
                try await normalizeForBehavior(to: .standing, token: token)
                try ensureCurrent(token)
                try await playAnimation(.sitTransition, phase: .expandedTimeline, token: token)
            }
        case .laying:
            switch renderState.pose {
            case .sleeping:
                let lay = DobermanAnimationDefinitions.animation(.lay)
                renderState = updatedState(
                    frame: lay.frames[0],
                    phase: .expandedTimeline,
                    pose: .laying,
                    action: .lay,
                    movementDuration: 0,
                    isWalking: false,
                    walkBobOffset: 0
                )
            case .laying:
                renderState = updatedState(
                    phase: .expandedTimeline,
                    pose: .laying,
                    movementDuration: 0,
                    isWalking: false,
                    walkBobOffset: 0
                )
            case .sitting:
                try await playAnimation(.standTransition, phase: .expandedTimeline, token: token)
                try ensureCurrent(token)
                try await playAnimation(.layTransition, phase: .expandedTimeline, token: token)
            case .standing, .walking:
                try await playAnimation(.layTransition, phase: .expandedTimeline, token: token)
            }
        case .sleeping:
            try await normalizeForBehavior(to: .laying, token: token)
        }
    }

    func performBehaviorAnimation(
        _ animationName: DobermanAnimationName,
        token: Int
    ) async throws {
        let animation = DobermanAnimationDefinitions.animation(animationName)

        if animation.loop {
            try await playLoop(
                animationName,
                phase: .expandedTimeline,
                holdMilliseconds: timingScale == 0
                    ? animation.frameDurationMilliseconds
                    : animation.holdMilliseconds
                    ?? animation.frames.count * animation.frameDurationMilliseconds,
                token: token
            )
            return
        }

        if let holdMilliseconds = animation.holdMilliseconds {
            try await holdAnimation(
                animationName,
                phase: .expandedTimeline,
                holdMilliseconds: timingScale == 0
                    ? animation.frameDurationMilliseconds
                    : holdMilliseconds,
                token: token
            )
            return
        }

        try await playAnimation(animationName, phase: .expandedTimeline, token: token)
    }

    func loopBehaviorAnimation(
        _ animationName: DobermanAnimationName,
        milliseconds: Int,
        token: Int
    ) async throws {
        try await playLoop(
            animationName,
            phase: .expandedTimeline,
            holdMilliseconds: milliseconds,
            token: token
        )
    }

    func walkForBehavior(toPercent percent: CGFloat, token: Int) async throws {
        try await playMovementStep(
            DobermanTimelineStep(action: .walk, moveTo: .percent(percent)),
            target: .percent(percent),
            token: token
        )
        try ensureCurrent(token)
        renderState = updatedState(
            pose: .standing,
            movementDuration: 0,
            isWalking: false,
            walkBobOffset: 0
        )
    }

    func sleepForBehavior(milliseconds: Int, token: Int) async throws {
        try await playLoop(
            .sleepLoop,
            phase: .expandedTimeline,
            holdMilliseconds: milliseconds,
            token: token
        )
    }

    func holdForBehavior(milliseconds: Int, token: Int) async throws {
        try ensureCurrent(token)
        setMovementDuration(0)
        try await sleep(milliseconds: milliseconds)
        try ensureCurrent(token)
    }

    private func startSleepLoop() {
        generation += 1
        let token = generation
        animationTask?.cancel()
        animationTask = Task { @MainActor [weak self] in
            await self?.runSleepLoop(token: token)
        }
    }

    private func runExpanded(token: Int) async {
        do {
            try ensureCurrent(token)
            setMovementDuration(0)
            try await playAnimation(.standFromLayTransition, phase: .waking, token: token)

            while true {
                try ensureCurrent(token)
                resetTimelineStart()
                for step in DobermanAnimationDefinitions.defaultTimeline {
                    try await playTimelineStep(step, token: token)
                }
            }
        } catch {
            return
        }
    }

    private func runClosed(token: Int) async {
        do {
            try ensureCurrent(token)
            setMovementDuration(0)

            let sequence = DobermanAnimationDefinitions.closeSequence(from: renderState.pose)
            for animationName in sequence {
                try await playAnimation(animationName, phase: .closing, token: token)
            }

            try await runSleepLoopThrowing(token: token)
        } catch {
            return
        }
    }

    private func runSleepLoop(token: Int) async {
        do {
            try await runSleepLoopThrowing(token: token)
        } catch {
            return
        }
    }

    private func runSleepLoopThrowing(token: Int) async throws {
        let sleepLoop = DobermanAnimationDefinitions.animation(.sleepLoop)
        var frameIndex = sleepLoop.frames.firstIndex(of: renderState.frame) ?? 0

        while true {
            try ensureCurrent(token)
            renderState = updatedState(
                frame: sleepLoop.frames[frameIndex],
                phase: .sleeping,
                pose: .sleeping,
                action: .sleepLoop,
                isWalking: false,
                walkBobOffset: 0
            )
            frameIndex = (frameIndex + 1) % sleepLoop.frames.count
            try await sleep(milliseconds: sleepLoop.frameDurationMilliseconds)
        }
    }

    private func playTimelineStep(_ step: DobermanTimelineStep, token: Int) async throws {
        if let target = step.moveTo {
            try await playMovementStep(step, target: target, token: token)
            return
        }

        let animation = DobermanAnimationDefinitions.animation(step.action)
        let holdMilliseconds = step.holdMilliseconds ?? animation.holdMilliseconds

        if animation.loop, let holdMilliseconds {
            try await playLoop(
                step.action,
                phase: .expandedTimeline,
                holdMilliseconds: holdMilliseconds,
                token: token
            )
            return
        }

        if let holdMilliseconds {
            try await holdAnimation(
                step.action,
                phase: .expandedTimeline,
                holdMilliseconds: holdMilliseconds,
                token: token
            )
            return
        }

        try await playAnimation(step.action, phase: .expandedTimeline, token: token)
    }

    private func playMovementStep(
        _ step: DobermanTimelineStep,
        target: DobermanMovementTarget,
        token: Int
    ) async throws {
        preservesRestoredDogPosition = false
        let animation = DobermanAnimationDefinitions.animation(step.action)
        let spriteWidth = DobermanAnimationDefinitions.frameWidth
            * DobermanAnimationDefinitions.defaultScale
        let proposedTargetX = DobermanAnimationDefinitions.targetX(
            for: target,
            stageWidth: expandedStageWidth,
            spriteWidth: spriteWidth,
            currentX: renderState.x
        )
        let targetX = DobermanAnimationDefinitions.visibleX(
            for: expandedStageWidth / 2 - spriteWidth / 2,
            stageWidth: expandedStageWidth,
            spriteWidth: spriteWidth
        )
        let intendedDistance = proposedTargetX - renderState.x
        let worldDistance = intendedDistance * DobermanAnimationDefinitions.worldTravelMultiplier
        let facingDirection: DobermanFacingDirection = intendedDistance < 0 ? .left : .right
        let movementMilliseconds = timingScale == 0
            ? animation.frameDurationMilliseconds
            : step.durationMilliseconds
            ?? DobermanAnimationDefinitions.movementDurationMilliseconds(
                for: intendedDistance
            )

        try ensureCurrent(token)
        renderState = updatedState(
            frame: animation.frames[0],
            phase: .expandedTimeline,
            pose: .walking,
            action: step.action,
            isWalking: true,
            walkBobOffset: 0,
            facingDirection: facingDirection
        )

        try await sleep(milliseconds: DobermanAnimationDefinitions.movementStartDelayMilliseconds)
        try ensureCurrent(token)
        renderState = updatedState(
            x: targetX,
            movementDuration: Double(movementMilliseconds) / 1000
        )
        // Publish the duration before changing world travel so a reversal starts
        // with the new walk's timing instead of inheriting the previous animation.
        worldTravel += worldDistance

        try await playFrames(
            animation.frames,
            action: step.action,
            phase: .expandedTimeline,
            pose: .walking,
            durationMilliseconds: movementMilliseconds,
            loop: true,
            token: token
        )

    }

    private func playAnimation(
        _ animationName: DobermanAnimationName,
        phase: DobermanPresentationPhase,
        token: Int
    ) async throws {
        let animation = DobermanAnimationDefinitions.animation(animationName)
        let pose = DobermanAnimationDefinitions.pose(after: animationName)

        try await playFrames(
            animation.frames,
            action: animationName,
            phase: phase,
            pose: pose,
            durationMilliseconds: animation.frames.count * animation.frameDurationMilliseconds,
            loop: false,
            token: token
        )

        try ensureCurrent(token)
        renderState = updatedState(
            phase: phase,
            pose: pose,
            action: animationName,
            movementDuration: 0,
            isWalking: animationName == .walk,
            walkBobOffset: 0
        )
    }

    private func holdAnimation(
        _ animationName: DobermanAnimationName,
        phase: DobermanPresentationPhase,
        holdMilliseconds: Int,
        token: Int
    ) async throws {
        let animation = DobermanAnimationDefinitions.animation(animationName)
        let pose = DobermanAnimationDefinitions.pose(after: animationName)

        try ensureCurrent(token)
        renderState = updatedState(
            frame: animation.frames[0],
            phase: phase,
            pose: pose,
            action: animationName,
            movementDuration: 0,
            isWalking: false,
            walkBobOffset: 0
        )

        try await sleep(milliseconds: holdMilliseconds)
    }

    private func playLoop(
        _ animationName: DobermanAnimationName,
        phase: DobermanPresentationPhase,
        holdMilliseconds: Int,
        token: Int
    ) async throws {
        let animation = DobermanAnimationDefinitions.animation(animationName)
        let pose = DobermanAnimationDefinitions.pose(after: animationName)

        try await playFrames(
            animation.frames,
            action: animationName,
            phase: phase,
            pose: pose,
            durationMilliseconds: holdMilliseconds,
            loop: true,
            token: token
        )
    }

    private func playFrames(
        _ frames: [DobermanSpriteFrame],
        action: DobermanAnimationName,
        phase: DobermanPresentationPhase,
        pose: DobermanCanonicalPose,
        durationMilliseconds: Int,
        loop: Bool,
        token: Int
    ) async throws {
        guard !frames.isEmpty else { return }

        let frameDuration = DobermanAnimationDefinitions.animation(action).frameDurationMilliseconds
        let safeDuration = max(frameDuration, durationMilliseconds)
        var elapsed = 0
        var frameIndex = 0

        while elapsed < safeDuration {
            try ensureCurrent(token)
            let bobOffset = walkingBobOffset(action: action, elapsedMilliseconds: elapsed)
            renderState = updatedState(
                frame: frames[frameIndex],
                phase: phase,
                pose: pose,
                action: action,
                isWalking: action == .walk,
                walkBobOffset: bobOffset
            )

            try await sleep(milliseconds: frameDuration)
            elapsed += frameDuration

            if loop {
                frameIndex = (frameIndex + 1) % frames.count
            } else {
                frameIndex = min(frameIndex + 1, frames.count - 1)
            }
        }
    }

    private func resetTimelineStart() {
        let spriteWidth = DobermanAnimationDefinitions.frameWidth
            * DobermanAnimationDefinitions.defaultScale
        renderState = updatedState(
            x: DobermanAnimationDefinitions.visibleX(
                for: expandedStageWidth / 2 - spriteWidth / 2,
                stageWidth: expandedStageWidth,
                spriteWidth: spriteWidth
            ),
            movementDuration: 0,
            isWalking: false,
            walkBobOffset: 0
        )
    }

    private func setMovementDuration(_ duration: TimeInterval) {
        renderState = updatedState(movementDuration: duration)
    }

    private func walkingBobOffset(
        action: DobermanAnimationName,
        elapsedMilliseconds: Int
    ) -> CGFloat {
        guard action == .walk else { return 0 }
        let step = max(1, DobermanAnimationDefinitions.walkingBobStepMilliseconds)
        return (elapsedMilliseconds / step).isMultiple(of: 2) ? 0 : -1
    }

    private func ensureCurrent(_ token: Int) throws {
        if Task.isCancelled || generation != token {
            throw CancellationError()
        }
    }

    private func sleep(milliseconds: Int) async throws {
        let scaledMilliseconds = Double(max(0, milliseconds)) * timingScale
        guard scaledMilliseconds > 0 else {
            await Task.yield()
            try Task.checkCancellation()
            return
        }

        try await Task.sleep(nanoseconds: UInt64(scaledMilliseconds * 1_000_000))
    }

    private func updatedState(
        frame: DobermanSpriteFrame? = nil,
        phase: DobermanPresentationPhase? = nil,
        pose: DobermanCanonicalPose? = nil,
        action: DobermanAnimationName? = nil,
        x: CGFloat? = nil,
        movementDuration: TimeInterval? = nil,
        isWalking: Bool? = nil,
        walkBobOffset: CGFloat? = nil,
        facingDirection: DobermanFacingDirection? = nil
    ) -> DobermanRenderState {
        DobermanRenderState(
            frame: frame ?? renderState.frame,
            phase: phase ?? renderState.phase,
            pose: pose ?? renderState.pose,
            currentAction: action ?? renderState.currentAction,
            x: x ?? renderState.x,
            movementDuration: movementDuration ?? renderState.movementDuration,
            isWalking: isWalking ?? renderState.isWalking,
            walkBobOffset: walkBobOffset ?? renderState.walkBobOffset,
            facingDirection: facingDirection ?? renderState.facingDirection
        )
    }
}

struct DobermanExpandedActivityView: View {
    @ObservedObject var model: DobermanAnimationModel
    @ObservedObject var needsModel: DobermanNeedsModel
    @ObservedObject var behaviorController: DobermanBehaviorController
    @ObservedObject var sceneSession: DobermanSceneSessionController
    @Default(.dobermanShowStatusPanel) private var showStatusPanel

    var body: some View {
        HStack(spacing: 12) {
            DobermanSceneView(
                model: model,
                careFeedback: behaviorController.careFeedback,
                foodPlateState: behaviorController.foodPlateState,
                foodPlateSide: behaviorController.foodPlateSide,
                isFoodPlateInScene: behaviorController.isFoodPlateInScene,
                foodPlateSpawnTravel: behaviorController.foodPlateSpawnTravel,
                waterPlateState: behaviorController.waterPlateState,
                waterPlateSide: behaviorController.waterPlateSide,
                isWaterPlateInScene: behaviorController.isWaterPlateInScene,
                waterPlateSpawnTravel: behaviorController.waterPlateSpawnTravel,
                onRetireFoodPlate: behaviorController.retireFoodPlate,
                onRetireWaterPlate: behaviorController.retireWaterPlate,
                sceneSession: sceneSession
            )
                .frame(height: dobermanSceneContentHeight)
                .layoutPriority(1)

            if showStatusPanel {
                DobermanNeedsControlsView(
                    needsModel: needsModel,
                    behaviorController: behaviorController
                )
                .frame(width: 154)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, dobermanExpandedBottomMargin)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: OpenNotchHeightPreferenceKey.self,
                    value: clampedOpenNotchHeight(
                        proxy.size.height + dobermanOpenNotchHeightPadding
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityLabel("Doberman")
    }
}

struct DobermanSceneView: View {
    static let grassDepth: CGFloat = 1

    @ObservedObject var model: DobermanAnimationModel
    let careFeedback: DobermanCareFeedback?
    let foodPlateState: DobermanFoodPlateState
    let foodPlateSide: DobermanFoodPlateSide
    let isFoodPlateInScene: Bool
    let foodPlateSpawnTravel: CGFloat
    let waterPlateState: DobermanFoodPlateState
    let waterPlateSide: DobermanFoodPlateSide
    let isWaterPlateInScene: Bool
    let waterPlateSpawnTravel: CGFloat
    let onRetireFoodPlate: () -> Void
    let onRetireWaterPlate: () -> Void
    @ObservedObject var sceneSession: DobermanSceneSessionController
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Default(.dobermanReduceMotion) private var activityReduceMotion
    var body: some View {
        GeometryReader { proxy in
            let scale = DobermanAnimationDefinitions.expandedSceneScale
            let spriteEnvelopeWidth = DobermanAnimationDefinitions.frameWidth
                * DobermanAnimationDefinitions.defaultScale
            let spriteWidth = DobermanAnimationDefinitions.frameWidth * scale
            let spriteXInset = (spriteEnvelopeWidth - spriteWidth) / 2
            let spriteHeight = DobermanAnimationDefinitions.frameHeight * scale
            let groundY = max(0, proxy.size.height - spriteHeight - 12)
            let reducedMotion = systemReduceMotion || activityReduceMotion

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.black)

                DobermanSceneLayersView(
                    definition: .defaultNoon,
                    worldTravel: model.worldTravel,
                    seed: sceneSession.seed,
                    cloudEpoch: sceneSession.cloudEpoch,
                    isPaused: reducedMotion
                )

                if foodPlateState != .hidden {
                    let grassTravel = (model.worldTravel - foodPlateSpawnTravel) * Self.grassDepth
                    let adjacentSceneCenter = proxy.size.width / 2
                        + foodPlateSide.direction * proxy.size.width
                    DobermanScenePlateView(
                        imageName: foodPlateState == .full
                            ? "food-plate-full-day"
                            : "food-plate-empty-day",
                        accessibilityLabel: foodPlateState == .full
                            ? "Full food plate"
                            : "Empty food plate",
                        centerX: adjacentSceneCenter - (isFoodPlateInScene ? grassTravel : 0),
                        bottomY: max(0, proxy.size.height - 61),
                        viewportWidth: proxy.size.width,
                        exitAnimationDuration: reducedMotion ? 0.01 : model.renderState.movementDuration,
                        onRetire: onRetireFoodPlate
                    )
                }

                if waterPlateState != .hidden {
                    let grassTravel = (model.worldTravel - waterPlateSpawnTravel) * Self.grassDepth
                    let adjacentSceneCenter = proxy.size.width / 2
                        + waterPlateSide.direction * proxy.size.width
                    DobermanScenePlateView(
                        imageName: waterPlateState == .full
                            ? "water-plate-full"
                            : "water-plate-empty-day",
                        accessibilityLabel: waterPlateState == .full
                            ? "Full water plate"
                            : "Empty water plate",
                        centerX: adjacentSceneCenter - (isWaterPlateInScene ? grassTravel : 0),
                        bottomY: max(0, proxy.size.height - 61),
                        viewportWidth: proxy.size.width,
                        exitAnimationDuration: reducedMotion ? 0.01 : model.renderState.movementDuration,
                        onRetire: onRetireWaterPlate
                    )
                }

                DobermanSpriteSheetView(frame: model.renderState.frame, scale: scale)
                    .scaleEffect(x: model.renderState.facingDirection.scaleX, y: 1, anchor: .center)
                    .offset(
                        x: model.renderState.x + spriteXInset,
                        y: groundY - 17 + (reducedMotion ? 0 : model.renderState.walkBobOffset)
                    )
                    .animation(.linear(duration: reducedMotion ? 0.12 : model.renderState.movementDuration), value: model.renderState.x)
                    .accessibilityLabel("Doberman in the scene")

                sceneSession.activeTime.lightingOverlay
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                if let careFeedback {
                    DobermanCareFeedbackView(feedback: careFeedback)
                        .id(careFeedback.id)
                        .position(
                            x: model.renderState.x + spriteEnvelopeWidth / 2,
                            y: max(18, groundY - 16)
                        )
                        .allowsHitTesting(false)
                }
            }
            .animation(
                .linear(duration: reducedMotion ? 0.01 : model.renderState.movementDuration),
                value: model.worldTravel
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
            .onAppear { model.updateExpandedStageWidth(proxy.size.width) }
            .onChange(of: proxy.size.width) { _, width in model.updateExpandedStageWidth(width) }
        }
    }
}

private struct DobermanCareFeedbackView: View {
    let feedback: DobermanCareFeedback
    @State private var isPresented = false

    private var message: String {
        feedback.amount > 0 ? "+\(feedback.amount) \(feedback.kind.label)" : "Full"
    }

    var body: some View {
        Label(message, systemImage: feedback.kind.icon)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(feedback.kind.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.72), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
            .scaleEffect(isPresented ? 1 : 0.85)
            .offset(y: isPresented ? -16 : 0)
            .opacity(isPresented ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.35)) {
                    isPresented = true
                }
            }
            .accessibilityLabel(
                feedback.amount > 0
                    ? "Plus \(feedback.amount) \(feedback.kind.label)"
                    : "\(feedback.kind.label) full"
            )
    }
}

struct DobermanScenePlateView: View {
    static let size = CGSize(width: 35, height: 20)
    static let fadeOutDuration: TimeInterval = 0.5

    let imageName: String
    let accessibilityLabel: String
    let centerX: CGFloat
    let bottomY: CGFloat
    let viewportWidth: CGFloat
    let exitAnimationDuration: TimeInterval
    let onRetire: () -> Void
    @State private var hasEnteredViewport = false
    @State private var isFadingOut = false
    @State private var retirementTask: Task<Void, Never>?

    static func isWithinViewport(centerX: CGFloat, viewportWidth: CGFloat) -> Bool {
        let halfWidth = size.width / 2
        return centerX + halfWidth >= 0
            && centerX - halfWidth <= viewportWidth
    }

    static func isSafelyOffscreen(centerX: CGFloat, viewportWidth: CGFloat) -> Bool {
        let doubledEdgeDistance = size.width
        return centerX + doubledEdgeDistance < 0
            || centerX - doubledEdgeDistance > viewportWidth
    }

    var body: some View {
        Image(imageName)
            .resizable()
            .interpolation(.none)
            .antialiased(false)
            .scaledToFit()
            .frame(width: Self.size.width, height: Self.size.height)
            .offset(x: centerX - Self.size.width / 2, y: bottomY)
            .opacity(isFadingOut ? 0 : 1)
            .accessibilityLabel(accessibilityLabel)
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { updateLifecycle() }
            .onChange(of: centerX) { _, _ in updateLifecycle() }
            .onChange(of: viewportWidth) { _, _ in updateLifecycle() }
            .onDisappear { retirementTask?.cancel() }
    }

    private func updateLifecycle() {
        let intersectsViewport = Self.isWithinViewport(
            centerX: centerX,
            viewportWidth: viewportWidth
        )

        if intersectsViewport {
            retirementTask?.cancel()
            retirementTask = nil
            isFadingOut = false
            hasEnteredViewport = true
        } else if hasEnteredViewport && Self.isSafelyOffscreen(
            centerX: centerX,
            viewportWidth: viewportWidth
        ) {
            retirementTask?.cancel()
            retirementTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(exitAnimationDuration))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: Self.fadeOutDuration)) {
                    isFadingOut = true
                }
                try? await Task.sleep(for: .seconds(Self.fadeOutDuration))
                guard !Task.isCancelled else { return }
                onRetire()
            }
        }
    }
}

enum DobermanTileSequence {
    static func variantIndex(tileIndex: Int, seed: UInt64, variantCount: Int) -> Int {
        guard variantCount > 1 else { return 0 }

        var previous = Int(mixed(seed) % UInt64(variantCount))
        guard tileIndex != 0 else { return previous }

        let direction = tileIndex > 0 ? 1 : -1
        for step in stride(from: direction, through: tileIndex, by: direction) {
            let stepBits = UInt64(bitPattern: Int64(step))
            let salt: UInt64 = direction > 0 ? 0xA11C_E001 : 0x1E57_BA11
            let choice = Int(mixed(seed ^ stepBits ^ salt) % UInt64(variantCount - 1))
            previous = choice >= previous ? choice + 1 : choice
        }
        return previous
    }

    private static func mixed(_ value: UInt64) -> UInt64 {
        var result = value &+ 0x9E37_79B9_7F4A_7C15
        result = (result ^ (result >> 30)) &* 0xBF58_476D_1CE4_E5B9
        result = (result ^ (result >> 27)) &* 0x94D0_49BB_1331_11EB
        return result ^ (result >> 31)
    }
}

struct DobermanSceneLayersView: View {
    let definition: DobermanSceneDefinition
    let worldTravel: CGFloat
    let seed: UInt64
    let cloudEpoch: Date
    let isPaused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isPaused)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(cloudEpoch))
            ZStack(alignment: .topLeading) {
                ForEach(definition.flattenedLayers) { layer in
                    DobermanSceneLayerView(
                        layer: layer,
                        worldTravel: worldTravel,
                        elapsed: elapsed,
                        sceneSeed: seed
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct DobermanSceneLayerView: View {
    let layer: DobermanSceneLayerDefinition
    let worldTravel: CGFloat
    let elapsed: TimeInterval
    let sceneSeed: UInt64

    @ViewBuilder
    var body: some View {
        switch layer.content {
        case .fixed(let imageName, let fillsViewport):
            GeometryReader { proxy in
                Image(imageName)
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .frame(
                        width: fillsViewport
                            ? proxy.size.width
                            : DobermanSceneDefinition.displaySize.width,
                        height: proxy.size.height
                    )
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        case .tiled(let imageNames, let seedSalt):
            DobermanTiledSceneLayer(
                imageNames: imageNames,
                seed: sceneSeed ^ seedSalt,
                travel: worldTravel * layer.worldMovementRatio
            )
        case .drifting(let imageName, let pointsPerSecond):
            DobermanTiledSceneLayer(
                imageNames: [imageName],
                seed: 0,
                travel: worldTravel * layer.worldMovementRatio
                    + CGFloat(elapsed) * pointsPerSecond
            )
        }
    }
}

struct DobermanTiledSceneLayer: View, Animatable {
    let imageNames: [String]
    let seed: UInt64
    var travel: CGFloat

    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    var body: some View {
        GeometryReader { proxy in
            let tileWidth = max(
                1,
                proxy.size.height
                    * DobermanSceneDefinition.sourceSize.width
                    / DobermanSceneDefinition.sourceSize.height
            )
            let baseTileIndex = Int(floor(travel / tileWidth))
            let wrappedTravel = Self.wrappedOffset(for: travel, tileWidth: tileWidth)
            let firstX = -wrappedTravel - tileWidth
            let tileCount = Self.tileCount(viewportWidth: proxy.size.width, tileWidth: tileWidth)

            HStack(spacing: 0) {
                ForEach(0..<tileCount, id: \.self) { offset in
                    let tileIndex = baseTileIndex + offset - 1
                    let variantIndex = DobermanTileSequence.variantIndex(
                        tileIndex: tileIndex,
                        seed: seed,
                        variantCount: imageNames.count
                    )
                    if imageNames.indices.contains(variantIndex) {
                        Image(imageNames[variantIndex])
                            .resizable()
                            .interpolation(.none)
                            .antialiased(false)
                            .frame(width: tileWidth, height: proxy.size.height)
                    }
                }
            }
            .frame(width: CGFloat(tileCount) * tileWidth, alignment: .leading)
            .offset(x: firstX)
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .topLeading
            )
            .clipped()
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    static func tileCount(viewportWidth: CGFloat, tileWidth: CGFloat) -> Int {
        max(3, Int(ceil(max(0, viewportWidth) / max(1, tileWidth))) + 2)
    }

    static func wrappedOffset(for travel: CGFloat, tileWidth: CGFloat) -> CGFloat {
        let width = max(1, tileWidth)
        let remainder = travel.truncatingRemainder(dividingBy: width)
        return remainder >= 0 ? remainder : remainder + width
    }
}

/// Compatibility wrapper for callers and movement-math tests that use a single tile.
struct DobermanParallaxLayer: View, Animatable {
    let imageName: String
    var travel: CGFloat
    let depth: CGFloat
    var usesNearestNeighbor = false

    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    var body: some View {
        DobermanTiledSceneLayer(
            imageNames: [imageName],
            seed: 0,
            travel: travel * depth
        )
    }

    static func tileCount(viewportWidth: CGFloat, tileWidth: CGFloat) -> Int {
        DobermanTiledSceneLayer.tileCount(
            viewportWidth: viewportWidth,
            tileWidth: tileWidth
        )
    }

    static func wrappedOffset(for travel: CGFloat, tileWidth: CGFloat) -> CGFloat {
        DobermanTiledSceneLayer.wrappedOffset(for: travel, tileWidth: tileWidth)
    }
}

private extension DobermanSceneTime {
    @ViewBuilder
    var lightingOverlay: some View {
        switch self {
        case .night:
            Color(red: 0.02, green: 0.06, blue: 0.20).opacity(0.48)
        case .morning:
            Color(red: 1.0, green: 0.58, blue: 0.25).opacity(0.10)
        case .noon:
            Color.clear
        case .evening:
            Color(red: 0.20, green: 0.08, blue: 0.28).opacity(0.28)
        }
    }
}

struct DobermanNeedsControlsView: View {
    @ObservedObject var needsModel: DobermanNeedsModel
    @ObservedObject var behaviorController: DobermanBehaviorController

    var body: some View {
        VStack(spacing: 9) {
            if needsModel.isEnabled {
                DobermanNeedMeter(title: "Hunger", icon: "fork.knife", value: needsModel.hunger)
                DobermanNeedMeter(title: "Thirst", icon: "drop.fill", value: needsModel.thirst)
            }
            DobermanNeedMeter(title: "Energy", icon: "bolt.fill", value: needsModel.energy)

            HStack(spacing: 8) {
                careButton("Feed", icon: "fork.knife") { behaviorController.feed() }
                careButton("Give Water", icon: "drop.fill") { behaviorController.giveWater() }
            }
        }
        .font(.caption2)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.14)))
        .opacity(behaviorController.presentationPhase == .active ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: behaviorController.presentationPhase)
        .allowsHitTesting(behaviorController.presentationPhase == .active)
    }

    private func careButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 30, height: 26) }
            .buttonStyle(.bordered)
            .disabled(
                behaviorController.presentationPhase != .active
                    || behaviorController.isInteracting
                    || !needsModel.isEnabled
            )
            .help(title)
            .accessibilityLabel(title)
    }
}

struct DobermanNeedMeter: View {
    let title: String
    let icon: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: icon).frame(width: 12)
                Text(title)
                Spacer()
                if value < 25 { Text("Low").foregroundStyle(.orange) }
            }
            ProgressView(value: value, total: 100)
                .progressViewStyle(.linear)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(Int(value.rounded())) percent\(value < 25 ? ", low" : "")")
    }
}

struct DobermanLivePresentationView: View {
    @ObservedObject var model: DobermanAnimationModel

    var body: some View {
        GeometryReader { proxy in
            let scale = max(
                0.1,
                min(
                    proxy.size.width / DobermanAnimationDefinitions.frameWidth,
                    proxy.size.height / DobermanAnimationDefinitions.frameHeight
                )
            )

            DobermanSpriteSheetView(
                frame: model.renderState.frame,
                scale: scale
            )
            .scaleEffect(x: model.renderState.facingDirection.scaleX, y: 1, anchor: .center)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .accessibilityHidden(true)
        }
    }
}

struct DobermanSpriteSheetView: View {
    let frame: DobermanSpriteFrame
    let scale: CGFloat
    @Default(.dobermanPet) private var selectedPet

    var body: some View {
        Image(selectedPet.spriteAssetName)
            .resizable()
            .interpolation(.none)
            .antialiased(false)
            .frame(
                width: DobermanAnimationDefinitions.frameWidth
                    * CGFloat(DobermanAnimationDefinitions.sheetColumns)
                    * scale,
                height: DobermanAnimationDefinitions.frameHeight
                    * CGFloat(DobermanAnimationDefinitions.sheetRows)
                    * scale,
                alignment: .topLeading
            )
            .offset(
                x: -CGFloat(frame.column) * DobermanAnimationDefinitions.frameWidth * scale,
                y: -CGFloat(frame.row) * DobermanAnimationDefinitions.frameHeight * scale
            )
            .frame(
                width: DobermanAnimationDefinitions.frameWidth * scale,
                height: DobermanAnimationDefinitions.frameHeight * scale,
                alignment: .topLeading
            )
            .clipped()
    }
}

struct DobermanSettingsView: View {
    @ObservedObject var needsModel: DobermanNeedsModel
    @Default(.dobermanVirtualPetNeedsEnabled) private var needsEnabled
    @Default(.dobermanBackground) private var selectedBackground
    @Default(.dobermanPet) private var selectedPet
    @Default(.dobermanSceneTime) private var selectedTime

    var body: some View {
        Form {
            Section("Background") {
                Picker("Background", selection: $selectedBackground) {
                    ForEach(DobermanBackground.allCases) { background in
                        Text(background.displayName).tag(background)
                    }
                }
            }

            Section("Pet") {
                Picker("Pet", selection: $selectedPet) {
                    ForEach(DobermanPet.allCases) { pet in
                        Text(pet.displayName).tag(pet)
                    }
                }
            }

            Section("Time") {
                Picker("Time", selection: $selectedTime) {
                    ForEach(DobermanSceneTime.allCases) { time in
                        Text(time.displayName).tag(time)
                    }
                }

                Defaults.Toggle(key: .dobermanDynamicTimeEnabled) {
                    Text("Match time of day automatically")
                }

                Text("Automatic time matching updates when the activity opens using your current time zone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Defaults.Toggle(key: .dobermanVirtualPetNeedsEnabled) {
                    Text("Enable needs system")
                }

                if needsEnabled {
                    LabeledContent("Hunger", value: "\(Int(needsModel.hunger.rounded()))%")
                    LabeledContent("Thirst", value: "\(Int(needsModel.thirst.rounded()))%")
                    LabeledContent("Energy", value: "\(Int(needsModel.energy.rounded()))%")
                }
            }

            Section("Behavior") {
                Defaults.Toggle(key: .dobermanAutonomousBehaviorsEnabled) {
                    Text("Enable autonomous behaviors")
                }
                Defaults.Toggle(key: .dobermanRandomMovementEnabled) {
                    Text("Enable random movement")
                }
                Defaults.Toggle(key: .dobermanShowStatusPanel) {
                    Text("Show status panel")
                }
                Defaults.Toggle(key: .dobermanReduceMotion) {
                    Text("Reduce motion")
                }
            }
        }
        .accessibilityLabel("Doberman settings")
    }
}
