import Defaults
import SwiftUI

struct PomodoroActivityView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject var manager: PomodoroManager
    @ObservedObject private var webcamManager = WebcamManager.shared

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !isRunning)) { timeline in
            HStack(spacing: 20) {
                controls
                Spacer(minLength: 8)
                sessionContent(at: timeline.date)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pomodoro controls")
        .onAppear {
            manager.reconcile()
            if vm.isCameraExpanded {
                webcamManager.stopSession()
                vm.isCameraExpanded = false
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            controlButton(
                icon: primaryIcon,
                color: currentKind.tint,
                label: primaryLabel,
                action: primaryAction
            )

            controlButton(
                icon: "arrow.counterclockwise",
                color: .white,
                label: String(localized: "Reset Pomodoro"),
                action: manager.reset
            )
            .disabled(manager.snapshot == nil)
            .opacity(manager.snapshot == nil ? 0.35 : 1)

            controlButton(
                icon: "forward.end.fill",
                color: .white,
                label: String(localized: "Skip session"),
                action: manager.skip
            )
            .disabled(manager.snapshot == nil)
            .opacity(manager.snapshot == nil ? 0.35 : 1)
        }
    }

    private func sessionContent(at date: Date) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(currentKind.label)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(currentKind.tint)

                Text(phaseLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(PomodoroTimeFormatter.remaining(manager.remaining(at: date)))
                .font(.system(size: 48, weight: .regular, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(currentKind.tint)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .accessibilityLabel(accessibilityTime(at: date))

            HStack(spacing: 8) {
                Text(completedSessionsLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                cycleProgress
            }
        }
        .frame(maxWidth: 340, alignment: .trailing)
    }

    private var cycleProgress: some View {
        let target = max(1, Defaults[.pomodoroFocusSessionsBeforeLongBreak])
        let completedInCycle = manager.completedFocusSessions % target
        return HStack(spacing: 4) {
            ForEach(0..<target, id: \.self) { index in
                Circle()
                    .fill(index < completedInCycle ? Color.red : Color.white.opacity(0.18))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    private func controlButton(
        icon: String,
        color: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Circle()
                .fill(color.opacity(0.22))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(color)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var currentKind: PomodoroSessionKind {
        manager.currentKind
    }

    private var isRunning: Bool {
        manager.snapshot?.phase == .running
    }

    private var primaryIcon: String {
        manager.snapshot?.phase == .running ? "pause.fill" : "play.fill"
    }

    private var primaryLabel: String {
        switch manager.snapshot?.phase {
        case .running: return String(localized: "Pause Pomodoro")
        case .paused: return String(localized: "Resume Pomodoro")
        case .ready: return String(localized: "Start next session")
        case nil: return String(localized: "Start Pomodoro")
        }
    }

    private func primaryAction() {
        if manager.snapshot?.phase == .running {
            manager.pause()
        } else if manager.snapshot?.phase == .paused {
            manager.resume()
        } else {
            manager.start()
        }
    }

    private var phaseLabel: String {
        switch manager.snapshot?.phase {
        case .running: return String(localized: "In progress")
        case .paused: return String(localized: "Paused")
        case .ready: return String(localized: "Ready")
        case nil: return String(localized: "Ready")
        }
    }

    private var completedSessionsLabel: String {
        let count = manager.completedFocusSessions
        return count == 1
            ? String(localized: "1 focus completed")
            : String(localized: "\(count) focuses completed")
    }

    private func accessibilityTime(at date: Date) -> String {
        String(
            localized: "\(currentKind.label), \(PomodoroTimeFormatter.remaining(manager.remaining(at: date))) remaining"
        )
    }
}

struct PomodoroCompactView: View {
    @ObservedObject var manager: PomodoroManager

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !isRunning)) { timeline in
            if let snapshot = manager.snapshot {
                HStack(spacing: 6) {
                    Image(systemName: snapshot.kind.systemImage)
                    Text(PomodoroTimeFormatter.remaining(snapshot.remaining(at: timeline.date)))
                        .monospacedDigit()
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(snapshot.kind.tint)
                .accessibilityLabel(
                    String(
                        localized: "\(snapshot.kind.label), \(PomodoroTimeFormatter.remaining(snapshot.remaining(at: timeline.date))) remaining"
                    )
                )
            }
        }
    }

    private var isRunning: Bool {
        manager.snapshot?.phase == .running
    }
}

struct PomodoroLivePresentationView: View {
    @ObservedObject var manager: PomodoroManager

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !isRunning)) { timeline in
            if let snapshot = manager.snapshot {
                HStack(spacing: 5) {
                    if snapshot.phase == .paused {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 9, weight: .bold))
                    }

                    Text(PomodoroTimeFormatter.remaining(snapshot.remaining(at: timeline.date)))
                        .monospacedDigit()
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(snapshot.kind.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    String(
                        localized: "\(snapshot.kind.label), \(PomodoroTimeFormatter.remaining(snapshot.remaining(at: timeline.date))) remaining"
                    )
                )
            }
        }
    }

    private var isRunning: Bool {
        manager.snapshot?.phase == .running
    }
}

struct PomodoroSettingsView: View {
    @Default(.pomodoroFocusMinutes) private var focusMinutes
    @Default(.pomodoroShortBreakMinutes) private var shortBreakMinutes
    @Default(.pomodoroLongBreakMinutes) private var longBreakMinutes
    @Default(.pomodoroFocusSessionsBeforeLongBreak) private var sessionsBeforeLongBreak

    var body: some View {
        Form {
            Section {
                durationStepper(String(localized: "Focus"), value: $focusMinutes)
                durationStepper(String(localized: "Short break"), value: $shortBreakMinutes)
                durationStepper(String(localized: "Long break"), value: $longBreakMinutes)
            } header: {
                Text("Durations")
            } footer: {
                Text("Duration changes apply to the next session, not one already running or paused.")
            }

            Section {
                Stepper(value: $sessionsBeforeLongBreak, in: 1...12) {
                    HStack {
                        Text("Focuses before long break")
                        Spacer()
                        Text("\(sessionsBeforeLongBreak)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Defaults.Toggle(key: .pomodoroAutoStartNextSession) {
                    Text("Automatically start next session")
                }
            } header: {
                Text("Cycle")
            }
        }
        .navigationTitle("Pomodoro")
    }

    private func durationStepper(_ label: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: 1...120) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value.wrappedValue) min")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

private extension PomodoroSessionKind {
    var label: String {
        switch self {
        case .focus: return String(localized: "Focus")
        case .shortBreak: return String(localized: "Short Break")
        case .longBreak: return String(localized: "Long Break")
        }
    }

    var systemImage: String {
        switch self {
        case .focus: return "timer"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "figure.walk"
        }
    }

    var tint: Color {
        switch self {
        case .focus: return .red
        case .shortBreak: return .green
        case .longBreak: return .blue
        }
    }
}
