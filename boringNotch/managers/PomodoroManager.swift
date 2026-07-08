import AppKit
import Defaults
import Foundation

extension PomodoroConfiguration {
    static var current: PomodoroConfiguration {
        PomodoroConfiguration(
            focusDuration: TimeInterval(Defaults[.pomodoroFocusMinutes] * 60),
            shortBreakDuration: TimeInterval(Defaults[.pomodoroShortBreakMinutes] * 60),
            longBreakDuration: TimeInterval(Defaults[.pomodoroLongBreakMinutes] * 60),
            focusSessionsBeforeLongBreak: Defaults[.pomodoroFocusSessionsBeforeLongBreak],
            automaticallyStartsNextSession: Defaults[.pomodoroAutoStartNextSession]
        )
    }
}

@MainActor
final class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()

    @Published private(set) var snapshot: PomodoroSessionSnapshot?

    var isActive: Bool {
        snapshot?.phase == .running || snapshot?.phase == .paused
    }

    var currentKind: PomodoroSessionKind {
        snapshot?.kind ?? .focus
    }

    var completedFocusSessions: Int {
        snapshot?.completedFocusSessions ?? 0
    }

    private let defaults: UserDefaults
    private let now: () -> Date
    private let configuration: () -> PomodoroConfiguration
    private let managesBackgroundExecution: Bool
    private let persistenceKey = "pomodoroSessionSnapshot"

    private var completionTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        configuration: @escaping () -> PomodoroConfiguration = { .current },
        managesBackgroundExecution: Bool = true
    ) {
        self.defaults = defaults
        self.now = now
        self.configuration = configuration
        self.managesBackgroundExecution = managesBackgroundExecution
        restore()
        reconcile()
    }

    deinit {
        completionTask?.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
    }

    func start() {
        let date = now()
        let currentConfiguration = configuration()

        guard let current = snapshot else {
            update(
                .running(
                    kind: .focus,
                    duration: currentConfiguration.focusDuration,
                    startedAt: date,
                    completedFocusSessions: 0
                )
            )
            return
        }

        switch current.phase {
        case .ready:
            update(
                .running(
                    kind: current.kind,
                    duration: currentConfiguration.duration(for: current.kind),
                    startedAt: date,
                    completedFocusSessions: current.completedFocusSessions
                )
            )
        case .paused:
            resume()
        case .running:
            break
        }
    }

    func pause() {
        guard var current = snapshot, current.phase == .running else { return }
        let date = now()
        guard current.remaining(at: date) > 0 else {
            reconcile(at: date)
            return
        }
        current.pause(at: date)
        update(current)
    }

    func resume() {
        guard var current = snapshot, current.phase == .paused else { return }
        current.resume(at: now())
        update(current)
    }

    func reset() {
        snapshot = nil
        persist()
        updateBackgroundExecution()
    }

    func skip() {
        guard let current = snapshot else { return }
        transition(
            from: current,
            completed: false,
            at: now(),
            configuration: configuration()
        )
    }

    func reconcile() {
        reconcile(at: now())
    }

    func remaining(at date: Date) -> TimeInterval {
        snapshot?.remaining(at: date) ?? configuration().focusDuration
    }

    private func reconcile(at date: Date) {
        guard let current = snapshot,
              current.phase == .running,
              current.remaining(at: date) <= 0
        else {
            updateBackgroundExecution()
            return
        }

        transition(
            from: current,
            completed: true,
            at: date,
            configuration: configuration()
        )
    }

    private func transition(
        from current: PomodoroSessionSnapshot,
        completed: Bool,
        at date: Date,
        configuration: PomodoroConfiguration
    ) {
        var completedFocusSessions = current.completedFocusSessions
        let nextKind: PomodoroSessionKind

        switch current.kind {
        case .focus:
            if completed {
                completedFocusSessions += 1
                nextKind = completedFocusSessions.isMultiple(
                    of: configuration.focusSessionsBeforeLongBreak
                ) ? .longBreak : .shortBreak
            } else {
                nextKind = .shortBreak
            }
        case .shortBreak, .longBreak:
            nextKind = .focus
        }

        let nextDuration = configuration.duration(for: nextKind)
        if configuration.automaticallyStartsNextSession {
            update(
                .running(
                    kind: nextKind,
                    duration: nextDuration,
                    startedAt: date,
                    completedFocusSessions: completedFocusSessions
                )
            )
        } else {
            update(
                .ready(
                    kind: nextKind,
                    duration: nextDuration,
                    completedFocusSessions: completedFocusSessions
                )
            )
        }
    }

    private func update(_ newSnapshot: PomodoroSessionSnapshot) {
        snapshot = newSnapshot
        persist()
        updateBackgroundExecution()
    }

    private func restore() {
        guard let data = defaults.data(forKey: persistenceKey),
              let restored = try? JSONDecoder().decode(PomodoroSessionSnapshot.self, from: data),
              restored.isValid
        else {
            defaults.removeObject(forKey: persistenceKey)
            return
        }
        snapshot = restored
    }

    private func persist() {
        guard let snapshot else {
            defaults.removeObject(forKey: persistenceKey)
            return
        }
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: persistenceKey)
        }
    }

    private func updateBackgroundExecution() {
        completionTask?.cancel()
        completionTask = nil

        guard managesBackgroundExecution,
              let snapshot,
              snapshot.phase == .running
        else {
            removeLifecycleObservers()
            return
        }

        installLifecycleObserversIfNeeded()
        let delay = snapshot.remaining(at: now())
        guard delay > 0 else {
            reconcile()
            return
        }

        completionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.reconcile()
        }
    }

    private func installLifecycleObserversIfNeeded() {
        guard wakeObserver == nil, activeObserver == nil else { return }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }

        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
    }

    private func removeLifecycleObservers() {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
            self.activeObserver = nil
        }
    }
}
