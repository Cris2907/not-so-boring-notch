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

    /// Handles a horizontal trackpad gesture only when exactly three fingers are
    /// touching the trackpad, leaving existing one- and two-finger gestures alone.
    func threeFingerHorizontalTrackpadSwipe(
        isEnabled: Bool,
        action: @escaping (CGFloat, NSEvent.Phase) -> Void
    ) -> some View {
        background(
            ThreeFingerHorizontalTrackpadSwipeMonitor(
                isEnabled: isEnabled,
                action: action
            )
        )
    }
}

private struct ThreeFingerHorizontalTrackpadSwipeMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let action: (CGFloat, NSEvent.Phase) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.allowedTouchTypes = [.indirect]
        view.wantsRestingTouches = true
        context.coordinator.installMonitor(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(isEnabled: isEnabled, action: action)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, action: action)
    }

    @MainActor final class Coordinator: NSObject {
        private var isEnabled: Bool
        private var action: (CGFloat, NSEvent.Phase) -> Void
        private var monitor: Any?
        private weak var monitoredView: NSView?
        private var isTrackingTouches = false
        private var hasRecognizedHorizontalSwipe = false
        private var hasRejectedSwipe = false
        private var initialCentroid: CGPoint?
        private var previousCentroid: CGPoint?

        init(
            isEnabled: Bool,
            action: @escaping (CGFloat, NSEvent.Phase) -> Void
        ) {
            self.isEnabled = isEnabled
            self.action = action
        }

        func update(
            isEnabled: Bool,
            action: @escaping (CGFloat, NSEvent.Phase) -> Void
        ) {
            if self.isEnabled && !isEnabled {
                finishGesture(cancelled: true)
            }
            self.isEnabled = isEnabled
            self.action = action
        }

        func installMonitor(on view: NSView) {
            removeMonitor()
            monitoredView = view
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.gesture, .beginGesture, .endGesture, .swipe]
            ) { [weak self] event in
                self?.handleGestureEvent(event)
                return event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            finishGesture(cancelled: true)
            monitoredView = nil
        }

        private func handleGestureEvent(_ event: NSEvent) {
            guard let view = monitoredView,
                  event.window === view.window
            else { return }

            let location = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(location) else {
                finishGesture(cancelled: true)
                return
            }

            if event.type == .swipe {
                handleSystemSwipe(event)
                return
            }

            if event.type == .endGesture {
                finishGesture(cancelled: false)
                return
            }

            if event.type == .beginGesture {
                finishGesture(cancelled: true)
                return
            }

            guard isEnabled, event.type == .gesture else { return }

            updateTracking(with: event)
        }

        private func handleSystemSwipe(_ event: NSEvent) {
            guard isEnabled, event.deltaX != 0 else { return }

            // macOS may promote a three-finger trackpad gesture to a discrete
            // swipe event before raw touch movement reaches the application.
            // Feed that discrete movement through the same ruler sensitivity.
            finishGesture(cancelled: true)
            TrackpadGestureRouting.shared.isThreeFingerGestureActive = true
            action(0, .began)
            action(event.deltaX.sign == .minus ? -18 : 18, .changed)
            action(0, .ended)
            TrackpadGestureRouting.shared.isThreeFingerGestureActive = false
        }

        private func updateTracking(with event: NSEvent) {
            let touches = event.touches(matching: .touching, in: nil)
            guard touches.count == 3 else {
                if isTrackingTouches {
                    finishGesture(cancelled: true)
                }
                return
            }

            let sum = touches.reduce(CGPoint.zero) { partialResult, touch in
                CGPoint(
                    x: partialResult.x + touch.normalizedPosition.x,
                    y: partialResult.y + touch.normalizedPosition.y
                )
            }
            let centroid = CGPoint(
                x: sum.x / CGFloat(touches.count),
                y: sum.y / CGFloat(touches.count)
            )

            if !isTrackingTouches {
                isTrackingTouches = true
                initialCentroid = centroid
                previousCentroid = centroid
                return
            }

            guard !hasRejectedSwipe,
                  let initialCentroid,
                  let previousCentroid
            else { return }

            if !hasRecognizedHorizontalSwipe {
                let totalX = abs(centroid.x - initialCentroid.x)
                let totalY = abs(centroid.y - initialCentroid.y)
                guard max(totalX, totalY) >= 0.01 else { return }
                guard totalX >= 1.5 * totalY else {
                    hasRejectedSwipe = true
                    return
                }
                hasRecognizedHorizontalSwipe = true
                TrackpadGestureRouting.shared.isThreeFingerGestureActive = true
                action(0, .began)
            }

            let delta = (centroid.x - previousCentroid.x) * max(viewWidth, 1)
            self.previousCentroid = centroid
            guard abs(delta) > 0.1 else { return }
            action(delta, .changed)
        }

        private var viewWidth: CGFloat {
            monitoredView?.bounds.width ?? 0
        }

        private func finishGesture(cancelled: Bool) {
            if hasRecognizedHorizontalSwipe {
                action(0, cancelled ? .cancelled : .ended)
            }
            TrackpadGestureRouting.shared.isThreeFingerGestureActive = false
            resetTracking()
        }

        private func resetTracking() {
            isTrackingTouches = false
            hasRecognizedHorizontalSwipe = false
            hasRejectedSwipe = false
            initialCentroid = nil
            previousCentroid = nil
        }
    }
}

@MainActor
private final class TrackpadGestureRouting {
    static let shared = TrackpadGestureRouting()
    var isThreeFingerGestureActive = false
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

            // Three-finger horizontal gestures are reserved for controls inside
            // the current tab (for example, the timer ruler).
            guard !TrackpadGestureRouting.shared.isThreeFingerGestureActive else { return }

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
