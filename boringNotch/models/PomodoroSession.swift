import Foundation

enum PomodoroSessionKind: String, Codable, Equatable {
    case focus
    case shortBreak
    case longBreak
}

enum PomodoroSessionPhase: String, Codable, Equatable {
    case ready
    case running
    case paused
}

struct PomodoroConfiguration: Equatable {
    static let defaultFocusMinutes = 25
    static let defaultShortBreakMinutes = 5
    static let defaultLongBreakMinutes = 15
    static let defaultFocusSessionsBeforeLongBreak = 4

    let focusDuration: TimeInterval
    let shortBreakDuration: TimeInterval
    let longBreakDuration: TimeInterval
    let focusSessionsBeforeLongBreak: Int
    let automaticallyStartsNextSession: Bool

    static let standard = PomodoroConfiguration(
        focusDuration: TimeInterval(defaultFocusMinutes * 60),
        shortBreakDuration: TimeInterval(defaultShortBreakMinutes * 60),
        longBreakDuration: TimeInterval(defaultLongBreakMinutes * 60),
        focusSessionsBeforeLongBreak: defaultFocusSessionsBeforeLongBreak,
        automaticallyStartsNextSession: false
    )

    init(
        focusDuration: TimeInterval,
        shortBreakDuration: TimeInterval,
        longBreakDuration: TimeInterval,
        focusSessionsBeforeLongBreak: Int,
        automaticallyStartsNextSession: Bool
    ) {
        self.focusDuration = max(1, focusDuration)
        self.shortBreakDuration = max(1, shortBreakDuration)
        self.longBreakDuration = max(1, longBreakDuration)
        self.focusSessionsBeforeLongBreak = max(1, focusSessionsBeforeLongBreak)
        self.automaticallyStartsNextSession = automaticallyStartsNextSession
    }

    func duration(for kind: PomodoroSessionKind) -> TimeInterval {
        switch kind {
        case .focus: focusDuration
        case .shortBreak: shortBreakDuration
        case .longBreak: longBreakDuration
        }
    }
}

struct PomodoroSessionSnapshot: Codable, Equatable {
    var kind: PomodoroSessionKind
    var phase: PomodoroSessionPhase
    var duration: TimeInterval
    var accumulatedElapsed: TimeInterval
    var resumedAt: Date?
    var completedFocusSessions: Int

    static func running(
        kind: PomodoroSessionKind,
        duration: TimeInterval,
        startedAt: Date,
        completedFocusSessions: Int
    ) -> PomodoroSessionSnapshot {
        PomodoroSessionSnapshot(
            kind: kind,
            phase: .running,
            duration: max(1, duration),
            accumulatedElapsed: 0,
            resumedAt: startedAt,
            completedFocusSessions: max(0, completedFocusSessions)
        )
    }

    static func ready(
        kind: PomodoroSessionKind,
        duration: TimeInterval,
        completedFocusSessions: Int
    ) -> PomodoroSessionSnapshot {
        PomodoroSessionSnapshot(
            kind: kind,
            phase: .ready,
            duration: max(1, duration),
            accumulatedElapsed: 0,
            resumedAt: nil,
            completedFocusSessions: max(0, completedFocusSessions)
        )
    }

    var isValid: Bool {
        guard duration >= 1,
              accumulatedElapsed >= 0,
              accumulatedElapsed <= duration,
              completedFocusSessions >= 0
        else { return false }

        switch phase {
        case .running:
            return resumedAt != nil
        case .ready:
            return resumedAt == nil && accumulatedElapsed == 0
        case .paused:
            return resumedAt == nil
        }
    }

    func elapsed(at date: Date) -> TimeInterval {
        let activeElapsed: TimeInterval
        if phase == .running, let resumedAt {
            activeElapsed = max(0, date.timeIntervalSince(resumedAt))
        } else {
            activeElapsed = 0
        }
        return min(max(0, accumulatedElapsed + activeElapsed), duration)
    }

    func remaining(at date: Date) -> TimeInterval {
        max(0, duration - elapsed(at: date))
    }

    mutating func pause(at date: Date) {
        guard phase == .running else { return }
        accumulatedElapsed = elapsed(at: date)
        resumedAt = nil
        phase = .paused
    }

    mutating func resume(at date: Date) {
        guard phase == .paused else { return }
        resumedAt = date
        phase = .running
    }
}

enum PomodoroTimeFormatter {
    static func remaining(_ interval: TimeInterval) -> String {
        let wholeSeconds = Int(ceil(max(0, interval)))
        let hours = wholeSeconds / 3_600
        let minutes = (wholeSeconds % 3_600) / 60
        let seconds = wholeSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
