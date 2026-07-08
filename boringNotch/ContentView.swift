//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @ObservedObject var bluetoothAudioManager = BluetoothAudioManager.shared
    @ObservedObject var timeActivityManager = TimeActivityManager.shared
    @ObservedObject private var activityRegistry = ActivityRegistry.shared
    @ObservedObject private var liveProviderRegistry = LiveActivityPresentationProviderRegistry.shared
    @ObservedObject private var activityLivePresentationCoordinator = ActivityLivePresentationCoordinator.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false
    @State private var lastLoggedClosedActivityLivePresentation = ""
    @State private var showsTimerCompletionInterruption = false
    @State private var timerCompletionInterruptionTask: Task<Void, Never>?

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer

    @Default(.showNotHumanFace) var showNotHumanFace
    @Default(.clockShowInClosedNotch) var clockShowInClosedNotch

    // Shared interactive spring for movement/resizing to avoid conflicting animations
    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.72, blendDuration: 0)

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    private var requiredWindowHeight: CGFloat {
        notchWindowHeight(for: vm.notchSize.height)
    }

    private var topCornerRadius: CGFloat {
       ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.top
                : cornerRadiusInsets.closed.top
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.bottom
                : cornerRadiusInsets.closed.bottom
        )
    }

    private func computedChinWidth(
        livePresentationStack: ActivityLivePresentationStack
    ) -> CGFloat {
        var chinWidth: CGFloat = vm.closedNotchSize.width

        if coordinator.expandingView.type == .battery && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
        {
            chinWidth = 640
        } else if shouldShowBluetoothActivity && vm.notchState == .closed && !vm.hideOnClosed
        {
            chinWidth += bluetoothSneakSize.width
        } else if showsTimerCompletionInterruption && clockShowInClosedNotch
            && vm.notchState == .closed && !vm.hideOnClosed
        {
            chinWidth += (
                max(0, vm.effectiveClosedNotchHeight - 12)
                    + closedTimeActivityMinimumTextWidth
                    + 20
            )
        } else if let livePresentationWidth = activityLivePresentationAdditionalWidth(
            for: livePresentationStack
        ), vm.notchState == .closed && !vm.hideOnClosed
        {
            chinWidth += livePresentationWidth
        } else if !coordinator.expandingView.show && vm.notchState == .closed
            && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace]
            && !vm.hideOnClosed
        {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        }

        return chinWidth
    }

    private func activityLivePresentationAdditionalWidth(
        for stack: ActivityLivePresentationStack
    ) -> CGFloat? {
        let accessorySize = max(0, vm.effectiveClosedNotchHeight - 12)
        return stack.requiredAdditionalWidth(accessorySize: accessorySize)
    }

    private func closedActivityLivePresentationDisplayDescription(
        for stack: ActivityLivePresentationStack
    ) -> String {
        closedNotchLivePresentationDisplayDescription(
            for: stack,
            isNotchClosed: vm.notchState == .closed,
            hidesOnClosed: vm.hideOnClosed,
            interruption: activeClosedNotchInterruption
        )
    }

    private func logClosedActivityLivePresentationIfNeeded(_ description: String) {
        guard description != lastLoggedClosedActivityLivePresentation else { return }

        #if DEBUG
        ActivityLivePresentationDebugLogger.logContentViewPresentationChange(
            from: lastLoggedClosedActivityLivePresentation,
            to: description
        )
        #endif

        lastLoggedClosedActivityLivePresentation = description
    }

    private var activeClosedNotchInterruption: ClosedNotchLiveInterruption? {
        if coordinator.helloAnimationRunning {
            return .startup
        }
        if coordinator.expandingView.type == .battery
            && coordinator.expandingView.show
            && Defaults[.showPowerStatusNotifications]
        {
            return .battery
        }
        if shouldShowBluetoothActivity {
            return .bluetooth
        }
        if coordinator.sneakPeek.show
            && coordinator.sneakPeek.type != .music
            && coordinator.sneakPeek.type != .battery
            && coordinator.sneakPeek.type != .bluetooth
        {
            return .systemHUD
        }
        if coordinator.sneakPeek.show
            && coordinator.sneakPeek.type == .music
            && Defaults[.sneakPeekStyles] == .standard
        {
            return .mediaNotification
        }
        if showsTimerCompletionInterruption && clockShowInClosedNotch {
            return .timerCompletion
        }
        return nil
    }

    private var shouldShowBluetoothActivity: Bool {
        coordinator.sneakPeek.show
            && coordinator.sneakPeek.type == .bluetooth
            && Defaults[.showBluetoothHeadphoneNotifications]
    }

    private func updateTimerCompletionInterruption(for phase: TimeActivityPhase?) {
        timerCompletionInterruptionTask?.cancel()
        timerCompletionInterruptionTask = nil

        guard phase == .finished else {
            showsTimerCompletionInterruption = false
            return
        }

        showsTimerCompletionInterruption = true
        timerCompletionInterruptionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            showsTimerCompletionInterruption = false
        }
    }

    var body: some View {
        let livePresentationStack = selectedActivityLivePresentationStack(
            from: liveProviderRegistry.providers,
            snapshot: activityLivePresentationCoordinator.snapshot
        )
        let renderedLivePresentationDescription = closedActivityLivePresentationDisplayDescription(
            for: livePresentationStack
        )

        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()
        
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let mainLayout = NotchLayout(livePresentationStack: livePresentationStack)
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        vm.notchState == .open
                        ? Defaults[.cornerRadiusScaling]
                        ? (cornerRadiusInsets.opened.top) : (cornerRadiusInsets.opened.bottom)
                        : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                    // Keep the visible shell at a stable height. Applying this frame
                    // after the background/clip only fixes the outer layout frame,
                    // allowing short tab content to shrink the rendered notch.
                    .frame(
                        height: vm.notchState == .open ? vm.notchSize.height : nil,
                        alignment: .top
                    )
                    .background(.black)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear, radius: Defaults[.cornerRadiusScaling] ? 6 : 4
                    )
                    .padding(
                        .bottom,
                        vm.effectiveClosedNotchHeight == 0 ? 10 : 0
                    )
                
                mainLayout
                    .conditionalModifier(true) { view in
                        let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.684, blendDuration: 0)
                        let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
                        
                        return view
                            .animation(vm.notchState == .open ? openAnimation : closeAnimation, value: vm.notchState)
                            .animation(.smooth(duration: 0.25), value: vm.notchSize)
                            .animation(.smooth, value: gestureProgress)
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        doOpen()
                    }
                    .conditionalModifier(Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .up) { translation, phase in
                                handleUpGesture(translation: translation, phase: phase)
                            }
                    }
                    .horizontalTrackpadSwipe(
                        isEnabled: Defaults[.enableGestures]
                            && Defaults[.horizontalTabGestures]
                            && vm.notchState == .open,
                        threshold: max(50, Defaults[.gestureSensitivity] / 2)
                    ) { direction in
                        handleHorizontalSwipe(direction)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if self.vm.notchState == .open && !self.isHovering && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            withAnimation {
                                isHovering = false
                            }
                        }
                    }
                    .onChange(of: timeActivityManager.snapshot?.phase) { _, newPhase in
                        updateTimerCompletionInterruption(for: newPhase)
                    }
                    .onAppear {
                        updateTimerCompletionInterruption(
                            for: timeActivityManager.snapshot?.phase
                        )
                        logClosedActivityLivePresentationIfNeeded(
                            renderedLivePresentationDescription
                        )
                    }
                    .onChange(of: renderedLivePresentationDescription) { _, newValue in
                        logClosedActivityLivePresentationIfNeeded(newValue)
                    }
                    .onChange(of: activityRegistry.availableActivityIDs) {
                        let destination = resolvedNotchView(
                            coordinator.currentView,
                            availableActivityIDs: activityRegistry.availableActivityIDs,
                            includesShelf: Defaults[.boringShelf]
                        )
                        guard destination != coordinator.currentView else { return }
                        withAnimation(.smooth(duration: 0.25)) {
                            coordinator.currentView = destination
                        }
                    }
                    .onChange(of: vm.isBatteryPopoverActive) {
                        if !vm.isBatteryPopoverActive && !isHovering && vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if !self.vm.isBatteryPopoverActive && !self.isHovering && self.vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("Settings") {
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                        //                    Button("Edit") { // Doesnt work....
                        //                        let dn = DynamicNotch(content: EditPanelView())
                        //                        dn.toggle()
                        //                    }
                        //                    .keyboardShortcut("E", modifiers: .command)
                    }
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(
                            width: computedChinWidth(livePresentationStack: livePresentationStack),
                            height: vm.chinHeight
                        )
                }
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize.width, maxHeight: requiredWindowHeight, alignment: .top)
        .compositingGroup()
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(.smooth, value: gestureProgress)
        .background(NotchWindowHeightSynchronizer(height: requiredWindowHeight))
        .background(dragDetector)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                if vm.notchState == .closed {
                    coordinator.currentView = .shelf
                    doOpen()
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if vm.dropEvent {
                    vm.dropEvent = false
                    return
                }

                vm.dropEvent = false
                if !SharingStateManager.shared.preventNotchClose {
                    vm.close()
                }
            }
        }
    }

    @ViewBuilder
    func NotchLayout(livePresentationStack: ActivityLivePresentationStack) -> some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                if coordinator.helloAnimationRunning {
                    Spacer()
                    HelloAnimation(onFinish: {
                        vm.closeHello()
                    }).frame(
                        width: getClosedNotchSize().width,
                        height: 80
                    )
                    .padding(.top, 40)
                    Spacer()
                } else {
                    if coordinator.expandingView.type == .battery && coordinator.expandingView.show
                        && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
                    {
                        HStack(spacing: 0) {
                            HStack {
                                Text(batteryModel.statusText)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                            }

                            Rectangle()
                                .fill(.black)
                                .frame(width: vm.closedNotchSize.width + 10)

                            HStack {
                                BoringBatteryView(
                                    batteryWidth: 30,
                                    isCharging: batteryModel.isCharging,
                                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                                    isPluggedIn: batteryModel.isPluggedIn,
                                    levelBattery: batteryModel.levelBattery,
                                    isForNotification: true
                                )
                            }
                            .frame(width: 76, alignment: .trailing)
                        }
                        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
                      } else if shouldShowBluetoothActivity && vm.notchState == .closed && !vm.hideOnClosed {
                          BluetoothDeviceActivity(
                              device: bluetoothAudioManager.activeNotificationDevice,
                              profile: bluetoothAudioManager.activeProfile,
                              closedNotchWidth: vm.closedNotchSize.width,
                              height: vm.effectiveClosedNotchHeight
                          )
                          .transition(.opacity)
                      } else if coordinator.sneakPeek.show && Defaults[.inlineHUD] && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && (coordinator.sneakPeek.type != .bluetooth) && vm.notchState == .closed {
                          InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(.opacity)
                      } else if coordinator.sneakPeek.show && !Defaults[.inlineHUD] && coordinator.sneakPeek.type != .music && coordinator.sneakPeek.type != .battery && coordinator.sneakPeek.type != .bluetooth && vm.notchState == .closed {
                          Rectangle()
                              .fill(.clear)
                              .frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                      } else if showsTimerCompletionInterruption,
                                clockShowInClosedNotch,
                                vm.notchState == .closed,
                                !vm.hideOnClosed {
                          TimerCompletionInterruptionView()
                          .transition(.opacity)
                      } else if livePresentationStack.isVisible,
                                vm.notchState == .closed,
                                !vm.hideOnClosed {
                          ClosedActivityLivePresentationStackView(
                              stack: livePresentationStack,
                              openLiveActivity: openLiveActivityTab,
                              openMediaTab: openMediaTabFromChin
                          )
                          .id(livePresentationStack.identity)
                          .transition(.opacity)
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                          BoringFaceAnimation()
                       } else if vm.notchState == .open {
                           BoringHeader()
                               .frame(height: max(24, vm.effectiveClosedNotchHeight))
                               .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                       }

                      if coordinator.sneakPeek.show {
                          if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && (coordinator.sneakPeek.type != .bluetooth) && !Defaults[.inlineHUD] && vm.notchState == .closed {
                              SystemEventIndicatorModifier(
                                  eventType: $coordinator.sneakPeek.type,
                                  value: $coordinator.sneakPeek.value,
                                  icon: $coordinator.sneakPeek.icon,
                                  sendEventBack: { newVal in
                                      switch coordinator.sneakPeek.type {
                                      case .volume:
                                          VolumeManager.shared.setAbsolute(Float32(newVal))
                                      case .brightness:
                                          BrightnessManager.shared.setAbsolute(value: Float32(newVal))
                                      default:
                                          break
                                      }
                                  }
                              )
                              .padding(.bottom, 10)
                              .padding(.leading, 4)
                              .padding(.trailing, 8)
                          }
                          // Old sneak peek music
                          else if coordinator.sneakPeek.type == .music {
                              if vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard {
                                  HStack(alignment: .center) {
                                      Image(systemName: "music.note")
                                      GeometryReader { geo in
                                          MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName),  textColor: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray, minDuration: 1, frameWidth: geo.size.width)
                                      }
                                  }
                                  .foregroundStyle(.gray)
                                  .padding(.bottom, 10)
                              }
                          }
                      }
                  }
              }
              .conditionalModifier((coordinator.sneakPeek.show && (coordinator.sneakPeek.type == .music) && vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard) || (coordinator.sneakPeek.show && (coordinator.sneakPeek.type != .music) && (vm.notchState == .closed))) { view in
                  view
                      .fixedSize()
              }
              .zIndex(2)
            if vm.notchState == .open {
                VStack(spacing: 0) {
                    Group {
                        switch coordinator.currentView {
                        case .home:
                            NotchHomeView(albumArtNamespace: albumArtNamespace)
                        case .activity(let id):
                            if let activity = activityRegistry.activity(for: id),
                               activityRegistry.isActivityAvailable(id) {
                                ExpandedActivityView(activity: activity)
                            }
                        case .activities:
                            TimeActivityView()
                        case .shelf:
                            ShelfView()
                        }
                    }
                    .frame(maxHeight: .infinity)

                    NotchPaginationDots()
                        .frame(height: 18)
                }
                .id(coordinator.currentView)
                .transition(
                    .scale(scale: 0.8, anchor: .top)
                    .combined(with: .opacity)
                    .animation(.smooth(duration: 0.35))
                )
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
        .onPreferenceChange(OpenNotchHeightPreferenceKey.self) { height in
            vm.updateOpenNotchHeight(height)
        }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], delegate: GeneralDropTargetDelegate(isTargeted: $vm.generalDropTargeting))
    }

    @ViewBuilder
    func BoringFaceAnimation() -> some View {
        HStack {
            HStack {
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: max(0, vm.effectiveClosedNotchHeight - 12),
                        height: max(0, vm.effectiveClosedNotchHeight - 12)
                    )
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)
                MinimalFaceFeatures()
            }
        }.frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.boringShelf] && vm.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
            vm.dropEvent = true
            ShelfStateViewModel.shared.load(providers)
            return true
        }
        } else {
            EmptyView()
        }
    }

    private func doOpen() {
        withAnimation(animationSpring) {
            vm.open()
        }
    }

    private func openLiveActivityTab(for activityID: ActivityID) {
        guard vm.notchState == .closed,
              Defaults[.openNotchOnHover],
              !coordinator.sneakPeek.show,
              let destination = destinationView(forLiveActivityID: activityID),
              destination != coordinator.currentView else { return }

        withAnimation(.smooth(duration: 0.25)) {
            coordinator.currentView = destination
        }
    }

    private func destinationView(forLiveActivityID activityID: ActivityID) -> NotchViews? {
        if activityRegistry.isActivityAvailable(activityID) {
            return .activity(activityID)
        }

        switch activityID {
        case .media:
            return .home
        case .time:
            return .activities
        default:
            return nil
        }
    }

    private func openMediaTabFromChin() {
        guard vm.notchState == .closed,
              Defaults[.openNotchOnHover],
              Defaults[.openMediaTabOnChinHover],
              !coordinator.sneakPeek.show,
              coordinator.currentView != .home else { return }

        withAnimation(.smooth(duration: 0.25)) {
            coordinator.currentView = .home
        }
    }

    // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()
        
        if hovering {
            withAnimation(animationSpring) {
                isHovering = true
            }
            
            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }
            
            guard vm.notchState == .closed,
                  !coordinator.sneakPeek.show,
                  Defaults[.openNotchOnHover] else { return }
            
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.coordinator.sneakPeek.show else { return }
                    
                    self.doOpen()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    withAnimation(animationSpring) {
                        self.isHovering = false
                    }
                    
                    if self.vm.notchState == .open && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                        self.vm.close()
                    }
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleHorizontalSwipe(_ direction: HorizontalSwipeDirection) {
        guard vm.notchState == .open,
              let destination = horizontalSwipeDestination(
                from: coordinator.currentView,
                direction: direction,
                isInverted: Defaults[.invertHorizontalTabGestures],
                availableActivityIDs: activityRegistry.availableActivityIDs,
                includesShelf: Defaults[.boringShelf]
              )
        else { return }

        withAnimation(.smooth(duration: 0.3)) {
            coordinator.currentView = destination
        }

        if Defaults[.enableHaptics] {
            haptics.toggle()
        }
    }

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }

        if phase == .ended {
            withAnimation(animationSpring) { gestureProgress = .zero }
            return
        }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open else { return }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(animationSpring) {
                isHovering = false
            }
            if !SharingStateManager.shared.preventNotchClose { 
                gestureProgress = .zero
                vm.close()
            }

            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }
}

enum ClosedNotchLiveInterruption: String {
    case startup
    case battery
    case bluetooth
    case systemHUD = "system-hud"
    case mediaNotification = "media-notification"
    case timerCompletion = "timer-completion"
}

func closedNotchLivePresentationDisplayDescription(
    for stack: ActivityLivePresentationStack,
    isNotchClosed: Bool,
    hidesOnClosed: Bool,
    interruption: ClosedNotchLiveInterruption?
) -> String {
    let selection = stack.debugSelectionDescription

    guard isNotchClosed else {
        return "selected=\(selection) display=.hidden(notch-open)"
    }
    guard !hidesOnClosed else {
        return "selected=\(selection) display=.hidden(closed-notch-disabled)"
    }
    if let interruption {
        return "selected=\(selection) display=.interrupted(\(interruption.rawValue))"
    }
    return "selected=\(selection) display=\(selection)"
}

struct MediaLivePresentationAccessoryView: View {
    @ObservedObject var manager: MusicManager

    var body: some View {
        MediaLivePresentationArtworkView(manager: manager)
    }
}

private struct MediaLivePresentationArtworkView: View {
    @ObservedObject var manager: MusicManager

    var body: some View {
        Image(nsImage: manager.albumArt)
            .resizable()
            .scaledToFill()
            .clipShape(
                RoundedRectangle(cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed)
            )
            .accessibilityLabel("Media activity")
    }
}

struct MediaLivePresentationView: View {
    @ObservedObject var manager: MusicManager
    @Default(.useMusicVisualizer) private var useMusicVisualizer

    var body: some View {
        Group {
            if useMusicVisualizer {
                Rectangle()
                    .fill(
                        Defaults[.coloredSpectrogram]
                            ? Color(nsColor: manager.avgColor).gradient
                            : Color.gray.gradient
                    )
                    .mask {
                        AudioSpectrumView(isPlaying: $manager.isPlaying)
                            .frame(width: 16, height: 12)
                    }
            } else {
                LottieAnimationContainer()
            }
        }
        .accessibilityLabel(manager.isPlaying ? "Media playing" : "Media paused")
    }
}

struct MediaMinimalLivePresentationView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject var manager: MusicManager

    var body: some View {
        let artworkSize = max(0, vm.effectiveClosedNotchHeight - 12)

        MediaLivePresentationArtworkView(manager: manager)
            .frame(width: artworkSize, height: artworkSize)
    }
}

private struct ClosedActivityLivePresentationStackView: View {
    let stack: ActivityLivePresentationStack
    let openLiveActivity: (ActivityID) -> Void
    let openMediaTab: () -> Void

    var body: some View {
        switch stack {
        case .none:
            EmptyView()
        case .full(let activity):
            ClosedActivityFullLivePresentationView(
                activity: activity,
                openLiveActivity: openLiveActivity,
                openMediaTab: openMediaTab
            )
        case .split(let leading, let trailing):
            ClosedActivitySplitLivePresentationView(
                leadingActivity: leading,
                trailingActivity: trailing,
                openLiveActivity: openLiveActivity,
                openMediaTab: openMediaTab
            )
        }
    }
}

private struct ClosedActivityFullLivePresentationView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject var activity: AnyLiveActivityPresentationProvider
    let openLiveActivity: (ActivityID) -> Void
    let openMediaTab: () -> Void

    var body: some View {
        let accessorySize = max(0, vm.effectiveClosedNotchHeight - 12)
        let contentWidth = activity.livePresentationSizing.fullContentWidth.resolved(
            accessorySize: accessorySize
        )
        let edgeSpacing = closedActivityNotchEdgeSpacing(accessorySize: accessorySize)
        let centerWidth = max(
            0,
            vm.closedNotchSize.width - cornerRadiusInsets.closed.top
        )

        HStack(spacing: edgeSpacing) {
            activity.makeAccessoryView()
                .frame(width: accessorySize, height: accessorySize)
                .contentShape(Rectangle())
                .onHover { hovering in
                    guard hovering else { return }
                    openLiveActivity(activity.id)
                }

            Rectangle()
                .fill(.black)
                .frame(width: centerWidth)
                .contentShape(Rectangle())
                .onHover { hovering in
                    guard hovering else { return }
                    openMediaTab()
                }

            activity.makeFullView()
                .frame(width: contentWidth, alignment: .leading)
                .contentShape(Rectangle())
                .onHover { hovering in
                    guard hovering else { return }
                    openLiveActivity(activity.id)
                }
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

private struct ClosedActivitySplitLivePresentationView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject var leadingActivity: AnyLiveActivityPresentationProvider
    @ObservedObject var trailingActivity: AnyLiveActivityPresentationProvider
    let openLiveActivity: (ActivityID) -> Void
    let openMediaTab: () -> Void

    var body: some View {
        let accessorySize = max(0, vm.effectiveClosedNotchHeight - 12)

        HStack(spacing: closedActivityNotchEdgeSpacing(accessorySize: accessorySize)) {
            ClosedActivityMinimalLivePresentationView(
                activity: leadingActivity,
                iconPlacement: .trailing,
                alignment: .trailing,
                openLiveActivity: openLiveActivity
            )

            Rectangle()
                .fill(.black)
                .frame(
                    width: max(
                        0,
                        vm.closedNotchSize.width - cornerRadiusInsets.closed.top
                    )
                )
                .contentShape(Rectangle())
                .onHover { hovering in
                    guard hovering else { return }
                    openMediaTab()
                }

            ClosedActivityMinimalLivePresentationView(
                activity: trailingActivity,
                iconPlacement: .leading,
                alignment: .leading,
                openLiveActivity: openLiveActivity
            )
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

private struct ClosedActivityMinimalLivePresentationView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject var activity: AnyLiveActivityPresentationProvider

    let iconPlacement: ClosedActivityMinimalIconPlacement
    let alignment: Alignment
    let openLiveActivity: (ActivityID) -> Void

    var body: some View {
        let accessorySize = max(0, vm.effectiveClosedNotchHeight - 12)
        let showsAccessory = activity.showsAccessoryInMinimalPresentation
        let contentWidth = activity.livePresentationSizing.minimalContentWidth.resolved(
            accessorySize: accessorySize
        )
        let accessorySpacing: CGFloat = showsAccessory && contentWidth > 0 ? 6 : 0

        HStack(spacing: accessorySpacing) {
            if showsAccessory && iconPlacement == .leading {
                icon(accessorySize: accessorySize)
            }

            activity.makeMinimalView()
                .frame(width: contentWidth, alignment: iconPlacement.contentAlignment)

            if showsAccessory && iconPlacement == .trailing {
                icon(accessorySize: accessorySize)
            }
        }
        .frame(
            width: contentWidth + (showsAccessory ? accessorySize + accessorySpacing : 0),
            height: vm.effectiveClosedNotchHeight,
            alignment: alignment
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            guard hovering else { return }
            openLiveActivity(activity.id)
        }
    }

    private func icon(accessorySize: CGFloat) -> some View {
        activity.makeAccessoryView()
            .frame(width: accessorySize, height: accessorySize)
    }
}

private enum ClosedActivityMinimalIconPlacement {
    case leading
    case trailing

    var contentAlignment: Alignment {
        switch self {
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        }
    }
}

private struct NotchWindowHeightSynchronizer: NSViewRepresentable {
    let height: CGFloat

    func makeNSView(context: Context) -> WindowSizingView {
        WindowSizingView(height: height)
    }

    func updateNSView(_ nsView: WindowSizingView, context: Context) {
        nsView.updateHeight(height)
    }

    final class WindowSizingView: NSView {
        private var targetHeight: CGFloat

        init(height: CGFloat) {
            targetHeight = height
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            return nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyHeight()
        }

        func updateHeight(_ height: CGFloat) {
            targetHeight = height
            DispatchQueue.main.async { [weak self] in
                self?.applyHeight()
            }
        }

        private func applyHeight() {
            guard let window, abs(window.frame.height - targetHeight) > 0.5 else { return }
            var frame = window.frame
            let topEdge = frame.maxY
            frame.size.height = targetHeight
            frame.origin.y = topEdge - targetHeight
            window.setFrame(frame, display: true, animate: true)
        }
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }

}

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        return false
    }
}

#Preview {
    let vm = BoringViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
