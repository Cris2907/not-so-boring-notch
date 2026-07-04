//
//  TimeActivityView.swift
//  boringNotch
//

import AppKit
import Defaults
import SwiftUI

struct TimeActivityView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var manager = TimeActivityManager.shared
    @ObservedObject private var webcamManager = WebcamManager.shared

    @Default(.timerDefaultMinutes) private var defaultTimerMinutes
    @Default(.timerOptionSwipeAdjustment) private var timerOptionSwipeAdjustment
    @Default(.timerInvertSwipeDirection) private var timerInvertSwipeDirection
    @Default(.timerSwipeInertia) private var timerSwipeInertia
    @Default(.timerSwipeSensitivity) private var timerSwipeSensitivity
    @Default(.stopwatchShowCentiseconds) private var stopwatchShowCentiseconds

    @State private var selectedKind: TimeActivityKind = .timer
    @State private var selectedMinutes = Defaults[.timerDefaultMinutes]
    @State private var rulerOffset: CGFloat = 0

    private let minuteRange = 1...Int(TimeActivitySnapshot.maximumTimerDuration / 60)
    private let rulerTickSpacing: CGFloat = 18

    var body: some View {
        Group {
            if let snapshot = manager.snapshot {
                activeSession(snapshot)
            } else {
                setupView
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Time controls")
        .onAppear {
            if manager.snapshot == nil {
                selectedMinutes = min(max(defaultTimerMinutes, minuteRange.lowerBound), minuteRange.upperBound)
            }
            if vm.isCameraExpanded {
                webcamManager.stopSession()
                vm.isCameraExpanded = false
            }
        }
        .onChange(of: defaultTimerMinutes) {
            guard manager.snapshot == nil else { return }
            selectedMinutes = min(max(defaultTimerMinutes, minuteRange.lowerBound), minuteRange.upperBound)
        }
    }

    private var setupView: some View {
        VStack(spacing: 4) {
            Picker("Time activity", selection: $selectedKind) {
                Text("Timer").tag(TimeActivityKind.timer)
                Text("Stopwatch").tag(TimeActivityKind.stopwatch)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(.orange)
            .controlSize(.small)
            .frame(width: 190)
            .accessibilityLabel("Time activity type")

            if selectedKind == .timer {
                timerSetup
            } else {
                idleStopwatch
            }
        }
    }

    private var timerSetup: some View {
        VStack(spacing: 2) {
            TimerRuler(
                selectedMinutes: selectedMinutes,
                range: minuteRange,
                tickSpacing: rulerTickSpacing,
                offset: rulerOffset
            )
            .frame(height: 64)

            HStack(alignment: .center) {
                Button {
                    manager.startTimer(duration: selectedDuration)
                } label: {
                    Text("Start timer")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 18)
                        .frame(height: 36)
                        .background(.orange.opacity(0.2), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start \(selectedMinutes) minute timer")

                Spacer(minLength: 12)

                Text(TimeActivityFormatter.timer(selectedDuration))
                    .font(.system(size: 38, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Timer duration \(selectedMinutes) minutes")
            }
        }
        .contentShape(Rectangle())
        .optionHorizontalTrackpadSwipe(
            isEnabled: selectedKind == .timer && timerOptionSwipeAdjustment,
            allowsInertia: timerSwipeInertia
        ) { delta, phase in
            handleTimerSwipe(delta: delta, phase: phase)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timer duration selector")
        .accessibilityHint("Hold Option and swipe horizontally with two fingers to adjust the timer")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                selectedMinutes = min(selectedMinutes + 1, minuteRange.upperBound)
            case .decrement:
                selectedMinutes = max(selectedMinutes - 1, minuteRange.lowerBound)
            @unknown default:
                break
            }
        }
    }

    private var idleStopwatch: some View {
        activityLayout(
            label: "Stopwatch",
            time: stopwatchShowCentiseconds ? "00:00.00" : "00:00",
            primaryIcon: "play.fill",
            primaryLabel: "Start stopwatch",
            primaryAction: { manager.startStopwatch() },
            secondaryIcon: "arrow.counterclockwise",
            secondaryLabel: "Reset stopwatch",
            secondaryAction: {},
            secondaryEnabled: false
        )
    }

    @ViewBuilder
    private func activeSession(_ snapshot: TimeActivitySnapshot) -> some View {
        TimelineView(.animation(minimumInterval: updateInterval(for: snapshot))) { timeline in
            activityLayout(
                label: snapshot.kind == .timer ? "Timer" : "Stopwatch",
                time: displayText(for: snapshot, at: timeline.date),
                primaryIcon: snapshot.phase == .finished
                    ? "xmark"
                    : (snapshot.phase == .running ? "pause.fill" : "play.fill"),
                primaryLabel: snapshot.phase == .finished
                    ? "Dismiss timer"
                    : (snapshot.phase == .running ? "Pause" : "Resume"),
                primaryAction: {
                    if snapshot.phase == .finished {
                        manager.dismissCompletion()
                    } else if snapshot.phase == .running {
                        manager.pause()
                    } else {
                        manager.resume()
                    }
                },
                secondaryIcon: snapshot.kind == .timer ? "xmark" : "arrow.counterclockwise",
                secondaryLabel: snapshot.kind == .timer ? "Cancel" : "Reset",
                secondaryAction: { manager.reset() },
                secondaryEnabled: snapshot.phase != .finished,
                showsSecondary: snapshot.phase != .finished,
                accessibilityTime: accessibilityTime(for: snapshot, at: timeline.date)
            )
        }
    }

    private func activityLayout(
        label: String,
        time: String,
        primaryIcon: String,
        primaryLabel: String,
        primaryAction: @escaping () -> Void,
        secondaryIcon: String,
        secondaryLabel: String,
        secondaryAction: @escaping () -> Void,
        secondaryEnabled: Bool = true,
        showsSecondary: Bool = true,
        accessibilityTime: String? = nil
    ) -> some View {
        HStack(spacing: 18) {
            HStack(spacing: 14) {
                activityCircleButton(
                    icon: primaryIcon,
                    foreground: .orange,
                    background: .orange.opacity(0.28),
                    accessibilityLabel: primaryLabel,
                    action: primaryAction
                )

                if showsSecondary {
                    activityCircleButton(
                        icon: secondaryIcon,
                        foreground: .white,
                        background: .white.opacity(0.18),
                        accessibilityLabel: secondaryLabel,
                        action: secondaryAction
                    )
                    .disabled(!secondaryEnabled)
                    .opacity(secondaryEnabled ? 1 : 0.35)
                }
            }

            Spacer(minLength: 12)

            HStack(alignment: .lastTextBaseline, spacing: 14) {
                Text(label)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange)

                Text(time)
                    .font(.system(size: 48, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .accessibilityLabel(accessibilityTime ?? "\(label) \(time)")
            }
            .frame(maxWidth: 360, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func activityCircleButton(
        icon: String,
        foreground: Color,
        background: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Circle()
                .fill(background)
                .frame(width: 66, height: 66)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(foreground)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var selectedDuration: TimeInterval {
        TimeInterval(selectedMinutes * 60)
    }

    private func handleTimerSwipe(delta: CGFloat, phase: NSEvent.Phase) {
        guard selectedKind == .timer else { return }

        if phase == .began {
            rulerOffset = 0
            return
        }

        if phase == .ended || phase == .cancelled {
            withAnimation(.snappy(duration: 0.18)) {
                rulerOffset = 0
            }
            return
        }

        let sensitivity = max(timerSwipeSensitivity, 1)
        let directionalDelta = timerInvertSwipeDirection ? delta : -delta
        rulerOffset += directionalDelta * (rulerTickSpacing / sensitivity)

        while rulerOffset <= -rulerTickSpacing && selectedMinutes < minuteRange.upperBound {
            selectedMinutes += 1
            rulerOffset += rulerTickSpacing
            provideTimerIntervalFeedback()
        }

        while rulerOffset >= rulerTickSpacing && selectedMinutes > minuteRange.lowerBound {
            selectedMinutes -= 1
            rulerOffset -= rulerTickSpacing
            provideTimerIntervalFeedback()
        }

        if selectedMinutes == minuteRange.lowerBound && rulerOffset > 0 {
            rulerOffset = 0
        } else if selectedMinutes == minuteRange.upperBound && rulerOffset < 0 {
            rulerOffset = 0
        }
    }

    private func provideTimerIntervalFeedback() {
        guard Defaults[.enableHaptics] else { return }
        if selectedMinutes.isMultiple(of: 5) {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        } else {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func updateInterval(for snapshot: TimeActivitySnapshot) -> TimeInterval? {
        guard snapshot.phase == .running else { return nil }
        if snapshot.kind == .stopwatch {
            return stopwatchShowCentiseconds ? 0.03 : 0.25
        }
        return 0.25
    }

    private func displayText(for snapshot: TimeActivitySnapshot, at date: Date) -> String {
        if snapshot.phase == .finished { return "Done" }
        if snapshot.kind == .timer {
            return TimeActivityFormatter.timer(snapshot.remaining(at: date))
        }
        return TimeActivityFormatter.stopwatch(
            snapshot.elapsed(at: date),
            includesCentiseconds: stopwatchShowCentiseconds
        )
    }

    private func accessibilityTime(for snapshot: TimeActivitySnapshot, at date: Date) -> String {
        if snapshot.phase == .finished { return "Timer finished" }
        return snapshot.kind == .timer
            ? "Timer remaining \(TimeActivityFormatter.timer(snapshot.remaining(at: date)))"
            : "Stopwatch elapsed \(TimeActivityFormatter.stopwatch(snapshot.elapsed(at: date), includesCentiseconds: false))"
    }
}

private struct TimerRuler: View {
    let selectedMinutes: Int
    let range: ClosedRange<Int>
    let tickSpacing: CGFloat
    let offset: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let visibleTickCount = Int(ceil(geometry.size.width / tickSpacing / 2)) + 2

            Canvas { context, size in
                for relativeValue in -visibleTickCount...visibleTickCount {
                    let value = selectedMinutes + relativeValue
                    guard range.contains(value) else { continue }

                    let x = centerX + CGFloat(relativeValue) * tickSpacing + offset
                    let isMajor = value.isMultiple(of: 5)
                    let tickTop: CGFloat = isMajor ? 24 : 32
                    let tickBottom: CGFloat = 55

                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: tickTop))
                    tick.addLine(to: CGPoint(x: x, y: tickBottom))
                    context.stroke(
                        tick,
                        with: .color(.orange.opacity(isMajor ? 0.9 : 0.55)),
                        lineWidth: isMajor ? 2 : 1
                    )

                    if isMajor {
                        context.draw(
                            Text("\(value)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.orange.opacity(0.82)),
                            at: CGPoint(x: x, y: 10),
                            anchor: .center
                        )
                    }
                }

                var selectionTick = Path()
                selectionTick.move(to: CGPoint(x: centerX, y: 22))
                selectionTick.addLine(to: CGPoint(x: centerX, y: 57))
                context.stroke(
                    selectionTick,
                    with: .color(.white.opacity(0.95)),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )

                var pointer = Path()
                pointer.move(to: CGPoint(x: centerX, y: size.height - 5))
                pointer.addLine(to: CGPoint(x: centerX - 6, y: size.height))
                pointer.addLine(to: CGPoint(x: centerX + 6, y: size.height))
                pointer.closeSubpath()
                context.fill(pointer, with: .color(.orange))
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white, location: 0.08),
                        .init(color: .white, location: 0.92),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .accessibilityHidden(true)
    }
}

struct ClosedTimeActivityView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var manager = TimeActivityManager.shared
    @ObservedObject private var musicManager = MusicManager.shared
    @ObservedObject private var coordinator = BoringViewCoordinator.shared

    let showMedia: Bool
    let albumArtNamespace: Namespace.ID

    var body: some View {
        TimelineView(.animation(minimumInterval: updateInterval)) { timeline in
            Group {
                if showMedia {
                    mediaAndTimeActivity(at: timeline.date)
                } else {
                    timeActivity(at: timeline.date)
                }
            }
            .frame(height: vm.effectiveClosedNotchHeight)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(closedAccessibilityLabel(at: timeline.date))
        }
    }

    private var mediaAccessoryWidth: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - 12)
    }

    private func mediaAndTimeActivity(at date: Date) -> some View {
        HStack(spacing: 8) {
            leftActivity(at: date)
                .frame(width: mediaAccessoryWidth, alignment: .trailing)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        coordinator.currentView = .home
                    }
                }

            Rectangle()
                .fill(.black)
                .frame(width: max(0, vm.closedNotchSize.width - cornerRadiusInsets.closed.top))

            compactTimeActivity(at: date)
                .frame(width: mediaAccessoryWidth, alignment: .center)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        coordinator.currentView = .activities
                    }
                }
        }
    }

    private func timeActivity(at date: Date) -> some View {
        HStack(spacing: 8) {
            leftActivity(at: date)
                .frame(width: 88, alignment: .trailing)

            Rectangle()
                .fill(.black)
                .frame(width: max(0, vm.closedNotchSize.width - 20))

            rightActivity(at: date)
                .frame(width: 88, alignment: .leading)
        }
    }

    @ViewBuilder
    private func leftActivity(at date: Date) -> some View {
        if showMedia {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .scaledToFill()
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 12),
                    height: max(0, vm.effectiveClosedNotchHeight - 12)
                )
                .clipShape(RoundedRectangle(cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed))
                .accessibilityLabel("Media activity")
        } else if let snapshot = manager.snapshot {
            Image(systemName: snapshot.kind == .timer ? "timer" : "stopwatch.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func rightActivity(at date: Date) -> some View {
        Group {
            if let snapshot = manager.snapshot {
                if snapshot.phase == .finished {
                    Text("Done")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                } else if snapshot.kind == .timer {
                    if showMedia {
                        HStack(spacing: 5) {
                            TimeProgressRing(snapshot: snapshot, date: date)
                            Text(TimeActivityFormatter.timer(snapshot.remaining(at: date)))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    } else {
                        Text(TimeActivityFormatter.timer(snapshot.remaining(at: date)))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                            .contentTransition(.numericText())
                    }
                } else {
                    if showMedia {
                        HStack(spacing: 5) {
                            Image(systemName: "stopwatch.fill")
                            Text(TimeActivityFormatter.stopwatch(snapshot.elapsed(at: date), includesCentiseconds: false))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                        .foregroundStyle(.orange)
                    } else {
                        Text(TimeActivityFormatter.stopwatch(snapshot.elapsed(at: date), includesCentiseconds: false))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                            .contentTransition(.numericText())
                    }
                }
            }
        }
        .accessibilityLabel("Time activity")
    }

    @ViewBuilder
    private func compactTimeActivity(at date: Date) -> some View {
        if let snapshot = manager.snapshot {
            if snapshot.phase == .finished {
                Image(systemName: "timer")
                    .foregroundStyle(.orange)
            } else if snapshot.kind == .timer {
                TimeProgressRing(snapshot: snapshot, date: date)
            } else {
                Image(systemName: "stopwatch.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var updateInterval: TimeInterval? {
        guard let snapshot = manager.snapshot, snapshot.phase == .running else { return nil }
        return snapshot.kind == .stopwatch ? 0.1 : 0.25
    }

    private func compactText(for snapshot: TimeActivitySnapshot, at date: Date) -> String {
        if snapshot.phase == .finished { return "Timer Done" }
        if snapshot.kind == .timer {
            return TimeActivityFormatter.timer(snapshot.remaining(at: date))
        }
        return TimeActivityFormatter.stopwatch(snapshot.elapsed(at: date), includesCentiseconds: false)
    }

    private func closedAccessibilityLabel(at date: Date) -> String {
        guard let snapshot = manager.snapshot else { return "" }
        let timeDescription = compactText(for: snapshot, at: date)
        return showMedia ? "\(timeDescription), media playing" : timeDescription
    }
}

private struct TimeProgressRing: View {
    let snapshot: TimeActivitySnapshot
    let date: Date

    private var progress: Double {
        guard snapshot.duration > 0 else { return 0 }
        return min(max(snapshot.remaining(at: date) / snapshot.duration, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "timer")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.orange)
        }
        .frame(width: 20, height: 20)
    }
}
