//
//  PanGesture.swift
//  boringNotch
//
//  Created by Richard Kunkli on 21/08/2024.
//

import AppKit
import SwiftUI

enum PanDirection {
    case left, right, up, down

    var isHorizontal: Bool { self == .left || self == .right }
    var sign: CGFloat { (self == .right || self == .down) ? 1 : -1 }

    func signed(from translation: CGSize) -> CGFloat { (isHorizontal ? translation.width : translation.height) * sign }
    func signed(deltaX: CGFloat, deltaY: CGFloat) -> CGFloat { (isHorizontal ? deltaX : deltaY) * sign }
}

enum HorizontalSwipeDirection: Equatable {
    case left
    case right
}

struct HorizontalSwipeAccumulator {
    private(set) var threshold: CGFloat
    private(set) var accumulated: CGFloat = 0
    private(set) var direction: HorizontalSwipeDirection?
    private(set) var hasTriggered = false

    init(threshold: CGFloat) {
        self.threshold = max(1, threshold)
    }

    mutating func updateThreshold(_ threshold: CGFloat) {
        let sanitized = max(1, threshold)
        guard sanitized != self.threshold else { return }
        self.threshold = sanitized
        reset()
    }

    mutating func consume(delta: CGFloat, isEnabled: Bool = true) -> HorizontalSwipeDirection? {
        guard isEnabled else {
            reset()
            return nil
        }
        guard !hasTriggered, delta != 0 else { return nil }

        let incomingDirection: HorizontalSwipeDirection = delta < 0 ? .left : .right
        if direction != incomingDirection {
            direction = incomingDirection
            accumulated = abs(delta)
        } else {
            accumulated += abs(delta)
        }

        guard accumulated >= threshold else { return nil }
        hasTriggered = true
        return incomingDirection
    }

    mutating func reset() {
        accumulated = 0
        direction = nil
        hasTriggered = false
    }
}

func horizontalSwipeDestination(
    from currentView: NotchViews,
    direction: HorizontalSwipeDirection,
    isInverted: Bool,
    includesShelf: Bool
) -> NotchViews? {
    let orderedViews: [NotchViews] = includesShelf
        ? [.home, .activities, .shelf]
        : [.home, .activities]
    guard let currentIndex = orderedViews.firstIndex(of: currentView) else { return nil }

    let movesTowardRight = isInverted
        ? direction == .left
        : direction == .right
    let offset = movesTowardRight ? 1 : -1
    let destinationIndex = (currentIndex + offset + orderedViews.count) % orderedViews.count
    return orderedViews[destinationIndex]
}

extension View {
    func panGesture(direction: PanDirection, threshold: CGFloat = 4, action: @escaping (CGFloat, NSEvent.Phase) -> Void) -> some View {
        self
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let s = direction.signed(from: value.translation)
                        guard s > 0, s.magnitude >= threshold else { return }
                        action(s.magnitude, .changed)
                    }
                    .onEnded { _ in action(0, .ended) }
            )
            .background(ScrollMonitor(direction: direction, threshold: threshold, action: action))
    }

    func horizontalTrackpadSwipe(
        isEnabled: Bool,
        threshold: CGFloat,
        action: @escaping (HorizontalSwipeDirection) -> Void
    ) -> some View {
        background(
            HorizontalTrackpadSwipeMonitor(
                isEnabled: isEnabled,
                threshold: threshold,
                action: action
            )
        )
    }

    /// Handles precise horizontal scrolling only while Option is held. This keeps
    /// the gesture separate from normal two-finger tab navigation.
    func optionHorizontalTrackpadSwipe(
        isEnabled: Bool,
        allowsInertia: Bool,
        action: @escaping (CGFloat, NSEvent.Phase) -> Void
    ) -> some View {
        background(
            OptionHorizontalTrackpadSwipeMonitor(
                isEnabled: isEnabled,
                allowsInertia: allowsInertia,
                action: action
            )
        )
    }
}

private struct OptionHorizontalTrackpadSwipeMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let allowsInertia: Bool
    let action: (CGFloat, NSEvent.Phase) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            isEnabled: isEnabled,
            allowsInertia: allowsInertia,
            action: action
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isEnabled: isEnabled,
            allowsInertia: allowsInertia,
            action: action
        )
    }

    @MainActor final class Coordinator: NSObject {
        private var isEnabled: Bool
        private var allowsInertia: Bool
        private var action: (CGFloat, NSEvent.Phase) -> Void
        private var monitor: Any?
        private weak var monitoredView: NSView?
        private var endTask: Task<Void, Never>?
        private var isTracking = false

        init(
            isEnabled: Bool,
            allowsInertia: Bool,
            action: @escaping (CGFloat, NSEvent.Phase) -> Void
        ) {
            self.isEnabled = isEnabled
            self.allowsInertia = allowsInertia
            self.action = action
        }

        func update(
            isEnabled: Bool,
            allowsInertia: Bool,
            action: @escaping (CGFloat, NSEvent.Phase) -> Void
        ) {
            if (self.isEnabled && !isEnabled) || (self.allowsInertia && !allowsInertia && isTracking) {
                finishGesture(phase: .cancelled)
            }
            self.isEnabled = isEnabled
            self.allowsInertia = allowsInertia
            self.action = action
        }

        func installMonitor(on view: NSView) {
            removeMonitor()
            monitoredView = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return self.handleScroll(event) ? nil : event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            finishGesture(phase: .cancelled)
            monitoredView = nil
        }

        private func handleScroll(_ event: NSEvent) -> Bool {
            guard let view = monitoredView,
                  event.window === view.window
            else { return false }

            if event.momentumPhase == .cancelled || event.momentumPhase == .ended {
                let wasTracking = isTracking
                finishGesture(phase: event.momentumPhase == .cancelled ? .cancelled : .ended)
                return wasTracking
            }

            if !event.momentumPhase.isEmpty {
                guard isEnabled,
                      allowsInertia,
                      isTracking,
                      event.hasPreciseScrollingDeltas
                else { return false }
                return applyDelta(from: event)
            }

            if event.phase == .ended || event.phase == .cancelled {
                let wasTracking = isTracking
                if event.phase == .cancelled || !allowsInertia {
                    finishGesture(phase: event.phase == .cancelled ? .cancelled : .ended)
                } else {
                    scheduleEndTimeout()
                }
                return wasTracking
            }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard isEnabled,
                  modifiers.contains(.option),
                  event.hasPreciseScrollingDeltas
            else { return false }

            if !isTracking {
                isTracking = true
                action(0, .began)
            }

            return applyDelta(from: event)
        }

        private func applyDelta(from event: NSEvent) -> Bool {
            let absDX = abs(event.scrollingDeltaX)
            let absDY = abs(event.scrollingDeltaY)
            guard absDX >= 1.5 * absDY, absDX > 0.2 else { return false }

            let physicalDelta = event.isDirectionInvertedFromDevice
                ? -event.scrollingDeltaX
                : event.scrollingDeltaX
            action(physicalDelta, .changed)
            scheduleEndTimeout()
            return true
        }

        private func scheduleEndTimeout() {
            endTask?.cancel()
            endTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                finishGesture(phase: .ended)
            }
        }

        private func finishGesture(phase: NSEvent.Phase) {
            endTask?.cancel()
            endTask = nil
            if isTracking {
                action(0, phase)
            }
            isTracking = false
        }
    }
}

private struct HorizontalTrackpadSwipeMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let threshold: CGFloat
    let action: (HorizontalSwipeDirection) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            isEnabled: isEnabled,
            threshold: threshold,
            action: action
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, threshold: threshold, action: action)
    }

    @MainActor final class Coordinator: NSObject {
        private var isEnabled: Bool
        private var accumulator: HorizontalSwipeAccumulator
        private var action: (HorizontalSwipeDirection) -> Void
        private var monitor: Any?
        private var endTask: Task<Void, Never>?

        init(
            isEnabled: Bool,
            threshold: CGFloat,
            action: @escaping (HorizontalSwipeDirection) -> Void
        ) {
            self.isEnabled = isEnabled
            self.accumulator = HorizontalSwipeAccumulator(threshold: threshold)
            self.action = action
        }

        func update(
            isEnabled: Bool,
            threshold: CGFloat,
            action: @escaping (HorizontalSwipeDirection) -> Void
        ) {
            if self.isEnabled != isEnabled {
                accumulator.reset()
            }
            self.isEnabled = isEnabled
            accumulator.updateThreshold(threshold)
            self.action = action
        }

        func installMonitor(on view: NSView) {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak view] event in
                guard let self, event.window === view?.window else { return event }
                self.handleScroll(event)
                return event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            endTask?.cancel()
            endTask = nil
            accumulator.reset()
        }

        private func handleScroll(_ event: NSEvent) {
            if event.phase == .ended || event.momentumPhase == .ended {
                finishGesture()
                return
            }

            guard isEnabled,
                  event.hasPreciseScrollingDeltas,
                  event.momentumPhase.isEmpty
            else { return }

            // Option + horizontal scroll is reserved for controls inside the
            // current tab (for example, the timer ruler).
            guard !event.modifierFlags.contains(.option) else { return }

            if event.phase == .began {
                accumulator.reset()
            }

            let absDX = abs(event.scrollingDeltaX)
            let absDY = abs(event.scrollingDeltaY)
            guard absDX >= 1.5 * absDY, absDX > 0.2 else { return }

            // Convert content-scrolling deltas back to physical finger direction so the
            // shortcut remains stable when Natural Scrolling is toggled.
            let physicalDelta = event.isDirectionInvertedFromDevice
                ? -event.scrollingDeltaX
                : event.scrollingDeltaX

            if let direction = accumulator.consume(delta: physicalDelta, isEnabled: isEnabled) {
                action(direction)
            }
            scheduleEndTimeout()
        }

        private func scheduleEndTimeout() {
            endTask?.cancel()
            endTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                finishGesture()
            }
        }

        private func finishGesture() {
            endTask?.cancel()
            endTask = nil
            accumulator.reset()
        }
    }
}

private struct ScrollMonitor: NSViewRepresentable {
    let direction: PanDirection
    let threshold: CGFloat
    let action: (CGFloat, NSEvent.Phase) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor(on: view)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.removeMonitor() }

    func makeCoordinator() -> Coordinator { 
        Coordinator(direction: direction, threshold: threshold, action: action) 
    }

    @MainActor final class Coordinator: NSObject {
        private let direction: PanDirection
        private let threshold: CGFloat
        private let action: (CGFloat, NSEvent.Phase) -> Void
        private var monitor: Any?
        private var accumulated: CGFloat = 0
        private var active = false
            private var endTask: Task<Void, Never>?
        private let noiseThreshold: CGFloat = 0.2

        init(direction: PanDirection, threshold: CGFloat, action: @escaping (CGFloat, NSEvent.Phase) -> Void) {
            self.direction = direction
            self.threshold = threshold
            self.action = action
        }

        private func scheduleEndTimeout() {
            // Cancel any existing scheduled end and schedule a new one.
            endTask?.cancel()
            endTask = Task { @MainActor in
                // If no new scroll event arrives within this window, consider the gesture ended.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                if active {
                    action(accumulated.magnitude, .ended)
                } else {
                    action(0, .ended)
                }
                active = false
                accumulated = 0
            }
        }

        func installMonitor(on view: NSView) {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self, weak view] event in
                guard let self = self, event.window === view?.window else { return event }
                self.handleScroll(event)
                return event
            }
        }

        func removeMonitor() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            accumulated = 0
            active = false
            endTask?.cancel()
            endTask = nil
        }

        private func handleScroll(_ event: NSEvent) {
            if event.phase == .ended || event.momentumPhase == .ended {
                if active {
                    action(accumulated.magnitude, .ended)
                } else {
                    action(0, .ended)
                }
                active = false
                accumulated = 0
                return
            }

            // Only consider scroll events that are primarily along the configured axis.
            let absDX = abs(event.scrollingDeltaX)
            let absDY = abs(event.scrollingDeltaY)
            // Require the movement along the gesture axis to be at least 1.5x the orthogonal axis.
            let axisDominanceFactor: CGFloat = 1.5
            let isAxisDominant: Bool = direction.isHorizontal ? (absDX >= axisDominanceFactor * absDY) : (absDY >= axisDominanceFactor * absDX)
            guard isAxisDominant else { return }

            // Scale non-precise (mouse wheel) scrolling deltas so they feel similar to
            // trackpad gestures.
            let raw = direction.signed(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
            let s = raw * scale
            guard s.magnitude > noiseThreshold else { return }
            accumulated = s > 0 ? accumulated + s : 0

            if !active && accumulated >= threshold {
                active = true
                action(accumulated.magnitude, .began)
            } else if active {
                action(accumulated.magnitude, .changed)
            }
            // Schedule a timeout to end the gesture if no further scroll events arrive.
            scheduleEndTimeout()
        }
    }
}
