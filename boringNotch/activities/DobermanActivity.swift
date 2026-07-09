import SwiftUI

extension ActivityID {
    static let doberman = ActivityID("builtin.doberman")
}

@MainActor
final class DobermanActivity: NotchActivity {
    static let activityID = ActivityID.doberman

    let id = activityID
    let metadata = ActivityMetadata(
        name: String(localized: "Doberman"),
        systemImage: "pawprint.fill",
        tint: .brown,
        summary: String(localized: "A sleeping Doberman companion for the notch.")
    )

    let model: DobermanAnimationModel
    @Published private(set) var expandedAppearanceCount = 0

    init(model: DobermanAnimationModel? = nil) {
        self.model = model ?? DobermanAnimationModel()
    }

    var isActive: Bool { true }

    var livePresentationState: ActivityLivePresentationState {
        expandedAppearanceCount == 0 ? .visible(priority: .low) : .hidden
    }

    let livePresentationSizing = LiveActivityPresentationSizing(
        fullContentWidth: .fixed(46),
        minimalContentWidth: .fixed(36)
    )

    func makeExpandedView() -> some View {
        DobermanExpandedActivityView(model: model)
    }

    func makeLivePresentationView() -> some View {
        DobermanLivePresentationView(model: model)
    }

    func makeMinimalLivePresentationView() -> some View {
        DobermanLivePresentationView(model: model)
    }

    func activityDidAppear() {
        expandedAppearanceCount += 1
        guard expandedAppearanceCount == 1 else { return }
        model.transitionToExpanded()
    }

    func activityDidDisappear() {
        guard expandedAppearanceCount > 0 else { return }
        expandedAppearanceCount -= 1
        guard expandedAppearanceCount == 0 else { return }
        model.transitionToClosed()
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

enum DobermanMovementTarget: Equatable, Sendable {
    case start
    case center
    case exit
    case percent(CGFloat)
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
    static let frameWidth: CGFloat = 40
    static let frameHeight: CGFloat = 30
    static let sheetColumns = 4
    static let sheetRows = 6
    static let frameDurationMilliseconds = 100
    static let sitHoldMilliseconds = 7000
    static let defaultScale: CGFloat = 3
    static let movementStartDelayMilliseconds = 50
    static let walkingBobStepMilliseconds = 180
    static let defaultStageWidth: CGFloat = 640

    static let defaultFrame = frame("1.1")

    private static let sitTransitionFrames = frames("3.1")
    private static let layTransitionFrames = frames("3.4", "4.1", "4.2")

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

    static func animation(_ name: DobermanAnimationName) -> DobermanAnimationDefinition {
        switch name {
        case .walk:
            return DobermanAnimationDefinition(
                frames: frames("1.1", "1.2", "1.3", "1.4", "2.1", "2.2", "2.3", "2.4"),
                loop: true
            )
        case .sitTransition:
            return DobermanAnimationDefinition(frames: sitTransitionFrames)
        case .sitHold:
            return DobermanAnimationDefinition(
                frames: frames("3.2"),
                holdMilliseconds: sitHoldMilliseconds
            )
        case .sitLookAround:
            return DobermanAnimationDefinition(
                frames: frames("3.3"),
                holdMilliseconds: sitHoldMilliseconds
            )
        case .standTransition:
            return DobermanAnimationDefinition(frames: Array(sitTransitionFrames.reversed()))
        case .layTransition:
            return DobermanAnimationDefinition(frames: layTransitionFrames)
        case .layHold:
            return DobermanAnimationDefinition(
                frames: frames("4.2"),
                holdMilliseconds: sitHoldMilliseconds
            )
        case .layLookAround:
            return DobermanAnimationDefinition(
                frames: frames("4.3"),
                holdMilliseconds: sitHoldMilliseconds
            )
        case .lay:
            return DobermanAnimationDefinition(
                frames: frames("4.4"),
                holdMilliseconds: sitHoldMilliseconds
            )
        case .sleepLoop:
            return DobermanAnimationDefinition(
                frames: frames("5.1", "5.2", "5.3", "5.4", "6.1", "6.2", "6.3", "6.4"),
                loop: true
            )
        case .standFromLayTransition:
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
        Int(round(min(9000, max(3500, abs(distance) * 7))))
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
        case .sitTransition, .sitHold, .sitLookAround:
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

    static func initial() -> DobermanRenderState {
        let sleep = DobermanAnimationDefinitions.animation(.sleepLoop)
        let spriteWidth = DobermanAnimationDefinitions.frameWidth
            * DobermanAnimationDefinitions.defaultScale
        let centerX = DobermanAnimationDefinitions.targetX(
            for: .percent(25),
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
            walkBobOffset: 0
        )
    }
}

@MainActor
final class DobermanAnimationModel: ObservableObject {
    @Published private(set) var renderState: DobermanRenderState

    private(set) var generation = 0
    private var expandedStageWidth = DobermanAnimationDefinitions.defaultStageWidth
    private let timingScale: Double
    private var animationTask: Task<Void, Never>?

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
    }

    func transitionToExpanded() {
        generation += 1
        let token = generation
        animationTask?.cancel()
        animationTask = Task { @MainActor [weak self] in
            await self?.runExpanded(token: token)
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
        let animation = DobermanAnimationDefinitions.animation(step.action)
        let spriteWidth = DobermanAnimationDefinitions.frameWidth
            * DobermanAnimationDefinitions.defaultScale
        let targetX = DobermanAnimationDefinitions.targetX(
            for: target,
            stageWidth: expandedStageWidth,
            spriteWidth: spriteWidth,
            currentX: renderState.x
        )
        let movementMilliseconds = step.durationMilliseconds
            ?? DobermanAnimationDefinitions.movementDurationMilliseconds(
                for: targetX - renderState.x
            )

        try ensureCurrent(token)
        renderState = updatedState(
            frame: animation.frames[0],
            phase: .expandedTimeline,
            pose: .walking,
            action: step.action,
            isWalking: true,
            walkBobOffset: 0
        )

        try await sleep(milliseconds: DobermanAnimationDefinitions.movementStartDelayMilliseconds)
        try ensureCurrent(token)
        renderState = updatedState(
            x: targetX,
            movementDuration: Double(movementMilliseconds) / 1000
        )

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
            x: DobermanAnimationDefinitions.startX(spriteWidth: spriteWidth),
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
        walkBobOffset: CGFloat? = nil
    ) -> DobermanRenderState {
        DobermanRenderState(
            frame: frame ?? renderState.frame,
            phase: phase ?? renderState.phase,
            pose: pose ?? renderState.pose,
            currentAction: action ?? renderState.currentAction,
            x: x ?? renderState.x,
            movementDuration: movementDuration ?? renderState.movementDuration,
            isWalking: isWalking ?? renderState.isWalking,
            walkBobOffset: walkBobOffset ?? renderState.walkBobOffset
        )
    }
}

struct DobermanExpandedActivityView: View {
    @ObservedObject var model: DobermanAnimationModel

    var body: some View {
        GeometryReader { proxy in
            let scale = DobermanAnimationDefinitions.defaultScale
            let spriteHeight = DobermanAnimationDefinitions.frameHeight * scale
            let y = max(0, proxy.size.height - spriteHeight - 10)

            ZStack(alignment: .topLeading) {
                DobermanSpriteSheetView(
                    frame: model.renderState.frame,
                    scale: scale
                )
                .offset(
                    x: model.renderState.x,
                    y: y + model.renderState.walkBobOffset
                )
                .animation(
                    .linear(duration: model.renderState.movementDuration),
                    value: model.renderState.x
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .onAppear {
                model.updateExpandedStageWidth(proxy.size.width)
            }
            .onChange(of: proxy.size.width) { _, width in
                model.updateExpandedStageWidth(width)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Doberman")
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
            .frame(width: proxy.size.width, height: proxy.size.height)
            .accessibilityHidden(true)
        }
    }
}

struct DobermanSpriteSheetView: View {
    let frame: DobermanSpriteFrame
    let scale: CGFloat

    var body: some View {
        Image("doberman-frames")
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
