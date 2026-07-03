//
//  TimeActivityView.swift
//  boringNotch
//

import SwiftUI

struct TimeActivityView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var manager = TimeActivityManager.shared
    @ObservedObject private var webcamManager = WebcamManager.shared

    @State private var selectedKind: TimeActivityKind = .timer
    @State private var hours = 0
    @State private var minutes = 5
    @State private var seconds = 0

    private let presets = [1, 5, 10, 25]

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
            if vm.isCameraExpanded {
                webcamManager.stopSession()
                vm.isCameraExpanded = false
            }
        }
    }

    private var setupView: some View {
        VStack(spacing: 8) {
            Picker("Time activity", selection: $selectedKind) {
                Text("Timer").tag(TimeActivityKind.timer)
                Text("Stopwatch").tag(TimeActivityKind.stopwatch)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(.orange)
            .frame(width: 220)
            .accessibilityLabel("Time activity type")

            if selectedKind == .timer {
                timerSetup
            } else {
                idleStopwatch
            }
        }
    }

    private var timerSetup: some View {
        HStack(spacing: 20) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    durationField("Hours", value: $hours, range: 0...99)
                    timeSeparator
                    durationField("Minutes", value: $minutes, range: 0...59)
                    timeSeparator
                    durationField("Seconds", value: $seconds, range: 0...59)
                }

                HStack(spacing: 6) {
                    ForEach(presets, id: \.self) { preset in
                        Button("\(preset)m") {
                            hours = 0
                            minutes = preset
                            seconds = 0
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.14), in: Capsule())
                        .overlay(Capsule().stroke(.orange.opacity(0.32), lineWidth: 1))
                        .accessibilityLabel("Set timer for \(preset) minutes")
                    }
                }
            }

            Spacer(minLength: 0)

            activityCircleButton(
                icon: "play.fill",
                foreground: .orange,
                background: .orange.opacity(0.28),
                accessibilityLabel: "Start timer"
            ) {
                manager.startTimer(duration: selectedDuration)
            }
            .disabled(!TimeActivitySnapshot.isValidTimerDuration(selectedDuration))
            .opacity(TimeActivitySnapshot.isValidTimerDuration(selectedDuration) ? 1 : 0.4)
        }
    }

    private var idleStopwatch: some View {
        activityLayout(
            label: "Stopwatch",
            time: "00:00.00",
            primaryIcon: "play.fill",
            primaryLabel: "Start stopwatch",
            primaryAction: { manager.startStopwatch() },
            secondaryIcon: "arrow.counterclockwise",
            secondaryLabel: "Reset stopwatch",
            secondaryAction: {},
            secondaryEnabled: false
        )
    }

    private var timeSeparator: some View {
        Text(":")
            .font(.system(size: 24, weight: .medium, design: .rounded))
            .foregroundStyle(.orange.opacity(0.75))
            .padding(.top, 11)
    }

    private func durationField(
        _ label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        TextField(
            label,
            value: Binding(
                get: { value.wrappedValue },
                set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }
            ),
            format: .number
        )
        .textFieldStyle(.plain)
        .multilineTextAlignment(.center)
        .font(.system(size: 24, weight: .medium, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.orange)
        .frame(width: 62, height: 36)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .top) {
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.gray)
                .offset(y: -11)
        }
        .padding(.top, 10)
        .accessibilityLabel(label)
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
        TimeInterval((hours * 3_600) + (minutes * 60) + seconds)
    }

    private func updateInterval(for snapshot: TimeActivitySnapshot) -> TimeInterval? {
        guard snapshot.phase == .running else { return nil }
        return snapshot.kind == .stopwatch ? 0.03 : 0.25
    }

    private func displayText(for snapshot: TimeActivitySnapshot, at date: Date) -> String {
        if snapshot.phase == .finished { return "Done" }
        if snapshot.kind == .timer {
            return TimeActivityFormatter.timer(snapshot.remaining(at: date))
        }
        return TimeActivityFormatter.stopwatch(
            snapshot.elapsed(at: date),
            includesCentiseconds: true
        )
    }

    private func accessibilityTime(for snapshot: TimeActivitySnapshot, at date: Date) -> String {
        if snapshot.phase == .finished { return "Timer finished" }
        return snapshot.kind == .timer
            ? "Timer remaining \(TimeActivityFormatter.timer(snapshot.remaining(at: date)))"
            : "Stopwatch elapsed \(TimeActivityFormatter.stopwatch(snapshot.elapsed(at: date), includesCentiseconds: false))"
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
            HStack(spacing: 6) {
                Image(systemName: snapshot.kind == .timer ? "timer" : "stopwatch.fill")
                    .foregroundStyle(.orange)
                Text(compactText(for: snapshot, at: date))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .foregroundStyle(.orange)
                    .contentTransition(.numericText())
            }
        }
    }

    @ViewBuilder
    private func rightActivity(at date: Date) -> some View {
        Group {
            if let snapshot = manager.snapshot {
                if snapshot.phase == .finished {
                    HStack(spacing: 5) {
                        Image(systemName: "timer")
                        Text("Done")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.orange)
                } else if snapshot.kind == .timer {
                    HStack(spacing: 5) {
                        TimeProgressRing(snapshot: snapshot, date: date)
                        if showMedia {
                            Text(TimeActivityFormatter.timer(snapshot.remaining(at: date)))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "stopwatch.fill")
                        if showMedia {
                            Text(TimeActivityFormatter.stopwatch(snapshot.elapsed(at: date), includesCentiseconds: false))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(.orange)
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
