//
//  BoringNotchWindow.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 06/08/24.
//

import Cocoa
import Combine

/// Grow the transparent viewport before SwiftUI receives the opening size.
/// Shrinking remains delayed by ContentView so outgoing content is not clipped.
@MainActor
final class NotchWindowSizeBinding {
    private var observation: AnyCancellable?

    init(window: NSPanel, viewModel: BoringViewModel) {
        observation = viewModel.$notchSize.removeDuplicates().sink { [weak window, weak viewModel] size in
            guard let window, let viewModel, size.width == openNotchSize.width else { return }
            let height = notchWindowHeight(for: size.height)
                + (viewModel.showsFloatingTabBar ? floatingTabBarGap + floatingTabBarHeight : 0)
            guard height > window.frame.height else { return }
            let screen = viewModel.screenUUID.flatMap { NSScreen.screen(withUUID: $0) } ?? window.screen
            let frame = topAnchoredNotchWindowFrame(window.frame, height: height, screenFrame: screen?.frame)
            window.setFrame(frame, display: false, animate: false)
        }
    }
}

@MainActor
final class NotchWindowKeyboardFocusBinding {
    private weak var window: NSPanel?
    private weak var viewModel: BoringViewModel?
    private var notchStateObservation: AnyCancellable?

    init(window: NSPanel, viewModel: BoringViewModel) {
        self.window = window
        self.viewModel = viewModel

        notchStateObservation = viewModel.$notchState
            .removeDuplicates()
            .sink { [weak self] state in
                guard state == .closed else { return }
                Task { @MainActor in
                    guard self?.viewModel?.notchState == .closed else { return }
                    self?.clearFirstResponder()
                }
            }
    }

    func firstResponderDidChange() {
        updateInteractionState()
    }

    func windowDidBecomeKey() {
        updateInteractionState()
    }

    func windowDidResignKey() {
        viewModel?.setKeyboardInteractionActive(false)
    }

    private func clearFirstResponder() {
        guard let window else { return }
        _ = window.makeFirstResponder(nil)
        updateInteractionState()
    }

    private func updateInteractionState() {
        guard let window else { return }
        let requiresKeyboardInput = window.isKeyWindow
            && (window.firstResponder as? NSView)?.needsPanelToBecomeKey == true
        viewModel?.setKeyboardInteractionActive(requiresKeyboardInput)
    }
}

class BoringNotchWindow: NSPanel {
    private var keyboardFocusBinding: NotchWindowKeyboardFocusBinding?
    private var sizeBinding: NotchWindowSizeBinding?

    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        
        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        
        isReleasedWhenClosed = false
        level = .mainMenu + 3
        hasShadow = false
    }
    
    func bindSizing(to viewModel: BoringViewModel) {
        sizeBinding = NotchWindowSizeBinding(window: self, viewModel: viewModel)
    }

    func bindKeyboardFocus(to viewModel: BoringViewModel) {
        keyboardFocusBinding = NotchWindowKeyboardFocusBinding(
            window: self,
            viewModel: viewModel
        )
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let accepted = super.makeFirstResponder(responder)
        if accepted {
            keyboardFocusBinding?.firstResponderDidChange()
        }
        return accepted
    }

    override func becomeKey() {
        super.becomeKey()
        keyboardFocusBinding?.windowDidBecomeKey()
    }

    override func resignKey() {
        super.resignKey()
        keyboardFocusBinding?.windowDidResignKey()
    }

    override var canBecomeKey: Bool { true }
    
    override var canBecomeMain: Bool {
        false
    }
}
