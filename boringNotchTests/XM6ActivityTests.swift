import AppKit
import Combine
import SonyHeadphonesKit
import SwiftUI
import XCTest
@testable import boringNotch

private final class XM6TestTransport: HeadphonesTransport {
    var onEvent: ((RFCOMMConnectionEvent) -> Void)?
    var disconnected = false
    func connect(toDeviceAddress address: String) {}
    func disconnect() { disconnected = true }
    func write(_ bytes: [UInt8]) {}
    func emit(_ payload: [UInt8], type: SonyMessageType = .command1) {
        onEvent?(.dataReceived(SonyMessage(type: type, sequenceNumber: 0, payload: payload).encode()))
    }
}

@MainActor
private final class XM6TestMonitor: XM6ConnectionMonitoring {
    var onWake: (() -> Void)?
    var onSleep: (() -> Void)?
    var onConnect: ((String) -> Void)?
    var onDisconnect: ((String) -> Void)?
    var started = false
    func start() { started = true }
    func stop() { started = false }
}

@MainActor
final class XM6ActivityTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var transports: [XM6TestTransport] = []
    private var monitor: XM6TestMonitor!
    private var enablement: ActivityEnablementStore!
    private let device = PairedDeviceInfo(id: "AA-BB-CC-DD-EE-FF", name: "My renamed headphones")

    override func setUp() {
        super.setUp()
        suite = "XM6ActivityTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        monitor = XM6TestMonitor()
        enablement = ActivityEnablementStore()
        transports = []
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }
    private func makeManager(remember: Bool = false, recoveryDelays: [UInt64] = [2_000_000_000, 5_000_000_000]) -> XM6Manager {
        if remember {
            defaults.set(device.id, forKey: "xm6.deviceAddress")
            defaults.set(device.name, forKey: "xm6.deviceName")
        }
        let controller = HeadphonesController(connectionFactory: { [unowned self] in
            let transport = XM6TestTransport(); self.transports.append(transport); return transport
        }, pairedDevicesProvider: { [device] in [device] }, defaults: defaults)
        return XM6Manager(controller: controller, defaults: defaults, enablement: enablement, monitor: monitor, recoveryDelays: recoveryDelays)
    }
    private func settle() async { for _ in 0..<30 { await Task.yield() } }
    private func finishConnection() async {
        transports.last?.onEvent?(.opened)
        await settle()
        transports.last?.emit([1, 0, 0, 0, 0, 0, 0, 0])
        await settle()
        transports.last?.emit([5, 1, 10] + Array("WH-1000XM6".utf8))
        await settle()
    }

    func testControlFailureRetriesWithoutAnotherBluetoothEventAndStopsAtLimit() async throws {
        let manager = makeManager(remember: true, recoveryDelays: [5_000_000, 5_000_000])
        manager.start()
        for count in 1...3 {
            XCTAssertEqual(transports.count, count)
            transports.last?.onEvent?(.failed("Control connection timed out"))
            await settle()
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertEqual(transports.count, 3)
        manager.stop()
    }

    func testManualDisconnectCancelsPendingControlRecovery() async throws {
        let manager = makeManager(remember: true, recoveryDelays: [20_000_000])
        manager.start()
        transports.last?.onEvent?(.failed("Control connection timed out"))
        await settle()
        manager.disconnect()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(transports.count, 1)
        manager.stop()
    }

    func testRegistrationMetadataNavigationAndSizing() throws {
        XCTAssertEqual(ActivityID.xm6.rawValue, "builtin.xm6")
        XCTAssertNotNil(ActivityRegistry.shared.activity(for: .xm6))
        let manager = makeManager()
        let activity = XM6Activity(manager: manager)
        let registry = try ActivityRegistry { activity }
        XCTAssertEqual(activity.metadata.name, "XM6")
        XCTAssertEqual(activity.metadata.preferredExpandedHeight, 388)
        XCTAssertEqual(activity.livePresentationSizing.fullContentWidth, .fixed(108))
        XCTAssertEqual(activity.livePresentationSizing.minimalContentWidth, .fixed(44))
        XCTAssertTrue(activity.supportsConfiguration)
        XCTAssertTrue(visibleNotchViews(availableActivityIDs: registry.availableActivityIDs, includesShelf: false).contains(.activity(.xm6)))
        XCTAssertEqual(activity.livePresentationState, .hidden)
        XCTAssertFalse(activity.isActive)
        let _: AnyView = try XCTUnwrap(registry.activity(for: .xm6)).makeExpandedView()
        registry.setActivityEnabled(false, for: .xm6)
        XCTAssertEqual(resolvedNotchView(.activity(.xm6), availableActivityIDs: registry.availableActivityIDs, includesShelf: false), .home)
    }

    func testFirstLaunchWaitsForConnectAndRemembersOnlySuccessfulConnection() async {
        let manager = makeManager()
        manager.start()
        XCTAssertTrue(transports.isEmpty)
        XCTAssertNil(manager.rememberedDevice)
        manager.connect(to: device)
        XCTAssertNil(manager.rememberedDevice)
        await finishConnection()
        XCTAssertEqual(manager.rememberedDevice, device)
        XCTAssertEqual(defaults.string(forKey: "xm6.deviceAddress"), device.id)
        manager.stop()
    }

    func testRememberedDeviceReconnectsOnLaunchWakeAndBluetoothEvent() async {
        let manager = makeManager(remember: true)
        manager.start()
        XCTAssertEqual(transports.count, 1)
        await finishConnection()
        monitor.onSleep?()
        XCTAssertFalse(manager.isConnected)
        monitor.onWake?()
        XCTAssertEqual(transports.count, 2)
        await finishConnection()
        monitor.onDisconnect?(device.id)
        XCTAssertEqual(manager.controller.connectionState, .disconnected)
        monitor.onConnect?("unrelated")
        XCTAssertEqual(transports.count, 2)
        monitor.onConnect?(device.id.lowercased())
        XCTAssertEqual(transports.count, 3)
        manager.stop()
    }

    func testManualDisconnectBlocksAutomaticReconnectUntilConnectOrRelaunch() async {
        let manager = makeManager(remember: true)
        manager.start()
        await finishConnection()
        manager.disconnect()
        monitor.onWake?()
        monitor.onConnect?(device.id)
        XCTAssertEqual(transports.count, 1)
        XCTAssertTrue(manager.manuallyDisconnected)
        manager.connect()
        XCTAssertEqual(transports.count, 2)
        XCTAssertFalse(manager.manuallyDisconnected)
        manager.disconnect()
        manager.stop()
        manager.start()
        XCTAssertEqual(transports.count, 3)
        manager.stop()
    }

    func testDisableCancelsConnectionAndStopsMonitoring() async {
        let manager = makeManager(remember: true)
        manager.start()
        XCTAssertTrue(monitor.started)
        let callback = transports[0].onEvent
        enablement.setEnabled(false, for: .xm6)
        XCTAssertFalse(monitor.started)
        XCTAssertTrue(transports[0].disconnected)
        callback?(.opened)
        monitor.onWake?()
        await settle()
        XCTAssertEqual(transports.count, 1)
        XCTAssertEqual(manager.controller.connectionState, .disconnected)
        enablement.setEnabled(true, for: .xm6)
        XCTAssertEqual(transports.count, 2)
        manager.stop()
    }

    func testAutomaticReconnectPreferencePersistsAndManualConnectStillWorks() {
        let manager = makeManager(remember: true)
        manager.automaticReconnect = false
        manager.start()
        monitor.onWake?()
        XCTAssertTrue(transports.isEmpty)
        XCTAssertEqual(defaults.object(forKey: "xm6.automaticReconnect") as? Bool, false)
        manager.connect()
        XCTAssertEqual(transports.count, 1)
        manager.stop()
    }

    func testExplicitDefaultPersistsAndWinsOverOneTimeConnections() async {
        let preferred = PairedDeviceInfo(id: "11-22-33-44-55-66", name: "Default accessory")
        let manager = makeManager()
        manager.automaticReconnect = false
        manager.setDefaultDevice(preferred)
        XCTAssertNil(manager.rememberedDevice)
        XCTAssertEqual(defaults.string(forKey: "xm6.defaultDeviceAddress"), preferred.id)
        manager.start()
        manager.connect()
        XCTAssertEqual(manager.controller.deviceAddress, preferred.id)
        await finishConnection()
        manager.disconnect()
        manager.connect(to: device)
        await finishConnection()
        XCTAssertEqual(manager.rememberedDevice, device)
        XCTAssertEqual(manager.defaultDevice, preferred)
        manager.disconnect()
        manager.connect()
        XCTAssertEqual(manager.controller.deviceAddress, preferred.id)
        manager.stop()
        let restored = makeManager()
        XCTAssertEqual(restored.defaultDevice, preferred)
        restored.start()
        XCTAssertFalse(restored.isConnecting)
        restored.connect()
        XCTAssertEqual(restored.controller.deviceAddress, preferred.id)
        restored.stop()
    }

    func testDefaultReconnectsBeforeFirstSuccessAndFiltersBluetoothEvents() async {
        let manager = makeManager()
        manager.setDefaultDevice(device)
        manager.start()
        XCTAssertTrue(monitor.started)
        XCTAssertEqual(manager.controller.deviceAddress, device.id)
        XCTAssertNil(manager.rememberedDevice)
        await finishConnection()
        monitor.onDisconnect?(device.id)
        monitor.onConnect?("another accessory")
        XCTAssertEqual(transports.count, 1)
        monitor.onConnect?(device.id.lowercased())
        XCTAssertEqual(transports.count, 2)
        XCTAssertEqual(manager.controller.deviceAddress, device.id)
        manager.stop()
    }

    func testChangingDefaultPreservesActiveSessionAndClearingRestoresLastConnected() async {
        let preferred = PairedDeviceInfo(id: "11-22-33-44-55-66", name: "Different accessory")
        let manager = makeManager(remember: true)
        manager.start()
        await finishConnection()
        manager.setDefaultDevice(preferred)
        XCTAssertTrue(manager.isConnected)
        XCTAssertEqual(manager.controller.deviceAddress, device.id)
        XCTAssertEqual(transports.count, 1)
        manager.disconnect()
        manager.connect()
        XCTAssertEqual(manager.controller.deviceAddress, preferred.id)
        manager.disconnect()
        manager.setDefaultDevice(nil)
        XCTAssertNil(defaults.object(forKey: "xm6.defaultDeviceAddress"))
        XCTAssertNil(defaults.object(forKey: "xm6.defaultDeviceName"))
        manager.connect()
        XCTAssertEqual(manager.controller.deviceAddress, device.id)
        manager.stop()
        XCTAssertNil(makeManager().defaultDevice)
    }

    func testRenderDefaultAccessorySettings() throws {
        let manager = makeManager()
        manager.setDefaultDevice(PairedDeviceInfo(id: "saved-but-unpaired", name: "Saved headphones"))
        try render(XM6SettingsView(manager: manager), name: "default-accessory-settings", width: 640, height: 520)
    }

    func testConnectedChinStateAndObservationPropagateThroughRegistry() async throws {
        let manager = makeManager(remember: true)
        let activity = XM6Activity(manager: manager)
        let registry = try ActivityRegistry { activity }
        let erased = try XCTUnwrap(registry.activity(for: .xm6))
        var changes = 0
        let observation = registry.objectWillChange.sink { changes += 1 }
        manager.start()
        await finishConnection()
        XCTAssertTrue(activity.isActive)
        XCTAssertEqual(erased.livePresentationState, .visible(priority: .normal))
        XCTAssertGreaterThan(changes, 0)
        let _: AnyView = erased.makeLivePresentationView()
        let _: AnyView = erased.makeMinimalLivePresentationView()
        let _: AnyView = erased.makeConfigurationView()
        manager.disconnect()
        XCTAssertEqual(erased.livePresentationState, .hidden)
        XCTAssertFalse(activity.isActive)
        withExtendedLifetime(observation) {}
        manager.stop()
    }

    func testFullSplitAndHiddenChinSelection() async throws {
        let manager = makeManager(remember: true)
        let activity = XM6Activity(manager: manager)
        let other = XM6CompanionActivity()
        let chinStore = ActivityChinVisibilityStore()
        let registry = try ActivityRegistry(chinVisibilityStore: chinStore) { activity; other }
        let providers = LiveActivityPresentationProviderRegistry(activityRegistry: registry)
        manager.start()
        await finishConnection()
        other.livePresentationState = .hidden
        let full = selectedActivityLivePresentationStack(from: providers.providers, snapshot: .empty)
        guard case .full(let selected) = full else { return XCTFail("Expected full XM6 chin") }
        XCTAssertEqual(selected.id, .xm6)
        XCTAssertEqual(full.requiredAdditionalWidth(accessorySize: 20), closedActivityFullPresentationAdditionalWidth(contentWidth: 108, accessorySize: 20))
        other.livePresentationState = .visible(priority: .normal)
        let split = selectedActivityLivePresentationStack(from: providers.providers, snapshot: .empty)
        guard case .split(let leading, let trailing) = split else { return XCTFail("Expected split chin") }
        XCTAssertEqual(Set([leading.id, trailing.id]), [.xm6, other.id])
        XCTAssertEqual(split.requiredAdditionalWidth(accessorySize: 20), 2 * (56 + 26) + 36)
        registry.setActivityShownOnChin(false, for: .xm6)
        XCTAssertFalse(providers.providers.contains { $0.id == .xm6 })
        registry.setActivityShownOnChin(true, for: .xm6)
        manager.disconnect()
        guard case .full(let remaining) = selectedActivityLivePresentationStack(from: providers.providers, snapshot: .empty) else {
            return XCTFail("XM6 must leave selection after disconnect")
        }
        XCTAssertEqual(remaining.id, other.id)
        manager.stop()
    }

    /// Static, hardware-free review artifacts cover the actual SwiftUI surfaces.
    func testRenderExpandedAndChinPresentations() async throws {
        let manager = makeManager()
        try render(XM6ActivityView(manager: manager), name: "disconnected", width: 640, height: 318)
        manager.start()
        manager.connect(to: device)
        await finishConnection()
        transports.last?.emit([0x25, 0, 100, 1])
        transports.last?.emit([0x69, 0x15, 1, 1, 1, 1, 7])
        transports.last?.emit([0x59, 4, 0xa0, 10] + Array(repeating: 6, count: 10))
        transports.last?.emit([0xe9, 9, 0, 1])
        transports.last?.emit([0xf9, 0x0c, 0, 1])
        transports.last?.emit([0xfd, 0x0c, 0, 1])
        transports.last?.emit([0xf9, 1, 0])
        transports.last?.emit([0x29, 5, 0x10, 0])
        transports.last?.emit([0x37, 2, 1] + Array("AA:BB:CC:DD:EE:FF".utf8) + [2, 0, 0, 0, 3] + Array("Mac".utf8) + [1], type: .command2)
        await settle()
        try render(XM6ActivityView(manager: manager), name: "connected", width: 520, height: 388)
        try render(XM6ActivityView(manager: manager), name: "connected-compact", width: 450, height: 388)
        let assignments = HeadphoneModelAssignments(defaults: defaults)
        assignments.assign("sony-wh-1000xm6", to: device.id)
        // The RFCOMM device is renamed; artwork comes from its address, without
        // reading or changing whichever device is currently the Mac audio output.
        XCTAssertEqual(assignments.profile(name: manager.controller.deviceName ?? "", address: manager.controller.deviceAddress).id,
                       "sony-wh-1000xm6")
        try render(XM6ActivityView(manager: manager, modelAssignments: assignments), name: "connected-assigned-xm6", width: 450, height: 388)
        try render(XM6DetailsView(controller: manager.controller, showsMoreSettings: true), name: "details-expanded", width: 426, height: 160)
        try render(XM6ChinView(manager: manager, minimal: false), name: "chin-full", width: 108, height: 32)
        try render(XM6ChinView(manager: manager, minimal: true), name: "chin-minimal", width: 44, height: 32)
        manager.stop()
    }

    func testRenderCachedSonyAnimationInLargerHeader() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SoundConnectApp/analysis/renders/WH-1000XM6-color-0x01-animated.png")
        guard FileManager.default.fileExists(atPath: fixture.path) else { throw XCTSkip("Local Sony render inspection fixture is not available") }
        let manager = makeManager()
        manager.start(); manager.connect(to: device); await finishConnection()
        defer { manager.stop() }
        let assignments = HeadphoneModelAssignments(defaults: defaults)
        let identities = SonyDeviceIdentityStore(assignments: assignments, loadArtwork: { _ in })
        identities.record(.init(modelName: "WH-1000XM6", series: 0x31, color: 1), address: device.id)
        let entry = try XCTUnwrap(identities.catalog.entry(model: "WH-1000XM6", color: 1))
        let artwork = SonyArtworkStore(files: [try XCTUnwrap(entry.animationURL): fixture])
        for width: CGFloat in [450, 520] {
            let view = XM6ActivityView(manager: manager, modelAssignments: assignments, identities: identities, artwork: artwork)
                .frame(width: width, height: 388).background(.black).environment(\.colorScheme, .dark)
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 388), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(1800))
            hosting.layoutSubtreeIfNeeded(); hosting.displayIfNeeded()
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("notch-xm6-review")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("sony-render-\(Int(width)).png"))
            let attachment = XCTAttachment(image: try XCTUnwrap(NSImage(data: bitmap.tiffRepresentation!)))
            attachment.name = "Sony render header \(Int(width))"; attachment.lifetime = .keepAlways; add(attachment)
            window.close()
        }
    }

    func testNoiseSelectorClampsDraggingAndSupportsRightToLeftLayout() {
        XCTAssertEqual(XM6NoiseModeSelector.index(at: -20, width: 300), 0)
        XCTAssertEqual(XM6NoiseModeSelector.index(at: 150, width: 300), 1)
        XCTAssertEqual(XM6NoiseModeSelector.index(at: 500, width: 300), 2)
        XCTAssertEqual(XM6NoiseModeSelector.index(at: 20, width: 300, isRightToLeft: true), 2)
        XCTAssertEqual(XM6NoiseModeSelector.index(at: 290, width: 300, isRightToLeft: true), 0)
        XCTAssertEqual(XM6NoiseModeSelector.index(at: 0, width: 0), 0)
    }

    func testBundledModeChangeSoundsDecodeWithoutPlaying() throws {
        for mode in AmbientSoundMode.allCases {
            let url = try XCTUnwrap(Bundle.main.url(
                forResource: XM6ModeChangeSound.resourceName(for: mode), withExtension: "wav",
                subdirectory: "NoiseControlSounds"))
            let sound = try XCTUnwrap(NSSound(contentsOf: url, byReference: true))
            XCTAssertGreaterThan(sound.duration, 0)
            XCTAssertLessThan(sound.duration, 2)
            try render(XM6NoiseModeSelector(selection: mode, select: { _ in }),
                       name: "noise-selector-" + XM6ModeChangeSound.resourceName(for: mode), width: 450, height: 48)
        }
    }

    func testMediaDuckingDoesNotCompoundAndRestoresOriginalPlayer() async {
        var volume = 0.8
        var writes: [Double] = []
        let target = XM6PlaybackDucker.Target(id: "player", read: { volume }, write: {
            volume = $0; writes.append($0)
        })
        let ducker = XM6PlaybackDucker()
        await ducker.begin(target)
        XCTAssertEqual(volume, 0.6, accuracy: 0.001)
        await ducker.begin(target)
        XCTAssertEqual(writes.count, 1)
        await ducker.end()
        XCTAssertEqual(volume, 0.8, accuracy: 0.001)
        XCTAssertFalse(ducker.isDucking)
    }

    func testMediaDuckingPreservesManualAdjustmentsAndSkipsUnsupportedPlayers() async {
        var volume = 0.8
        let target = XM6PlaybackDucker.Target(id: "player", read: { volume }, write: { volume = $0 })
        let ducker = XM6PlaybackDucker()
        await ducker.begin(target)
        volume = 0.4
        await ducker.end()
        XCTAssertEqual(volume, 0.4)
        await ducker.begin(nil)
        XCTAssertFalse(ducker.isDucking)
        await ducker.begin(.init(id: "unsupported", read: { nil }, write: { _ in XCTFail() }))
        XCTAssertFalse(ducker.isDucking)
        await ducker.begin(.init(id: "failed-write", read: { 0.8 }, write: { _ in }))
        XCTAssertFalse(ducker.isDucking)
    }

    func testSwitchingMediaPlayersRestoresOnlyCapturedPlayer() async {
        var first = 0.8
        var second = 0.4
        let ducker = XM6PlaybackDucker()
        await ducker.begin(.init(id: "first", read: { first }, write: { first = $0 }))
        await ducker.begin(.init(id: "second", read: { second }, write: { second = $0 }))
        XCTAssertEqual(first, 0.8, accuracy: 0.001)
        XCTAssertEqual(second, 0.3, accuracy: 0.001)
        await ducker.end()
        XCTAssertEqual(second, 0.4, accuracy: 0.001)
    }

    func testMediaDuckingRestoresIntegerPlayerVolume() async {
        var volume = 0.75
        let ducker = XM6PlaybackDucker()
        await ducker.begin(.init(id: "player", read: { volume }, write: { volume = Double(Int($0 * 100)) / 100 }))
        XCTAssertEqual(volume, 0.56, accuracy: 0.001)
        await ducker.end()
        XCTAssertEqual(volume, 0.75, accuracy: 0.001)
    }

    private func render<V: View>(_ view: V, name: String, width: CGFloat, height: CGFloat) throws {
        // ImageRenderer omits AppKit-backed scroll views. A real hosting view
        // exercises the same ScrollView/Picker/Slider rendering as the notch.
        let hosting = NSHostingView(rootView: view
            .frame(width: width, height: height)
            .background(.black)
            .environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.close() }
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let image = NSImage(size: hosting.bounds.size)
        image.addRepresentation(bitmap)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("notch-xm6-review", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("\(name).png"))
        let attachment = XCTAttachment(image: image)
        attachment.name = "XM6 \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        if name == "connected" || name == "connected-compact" || name == "connected-assigned-xm6" {
            let scroll = try XCTUnwrap(findScrollView(in: hosting))
            let document = try XCTUnwrap(scroll.documentView)
            XCTAssertLessThanOrEqual(document.bounds.height, scroll.contentView.bounds.height + 1,
                                     "Primary controls should fit without scrolling")
        }
        if name == "details-expanded" {
            let scroll = try XCTUnwrap(findScrollView(in: hosting))
            let document = try XCTUnwrap(scroll.documentView)
            XCTAssertGreaterThan(document.bounds.height, scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: document.bounds.height - scroll.contentView.bounds.height))
            scroll.reflectScrolledClipView(scroll.contentView)
            hosting.displayIfNeeded()
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("connected-scrolled.png"))
            let scrolled = XCTAttachment(image: NSImage(cgImage: try XCTUnwrap(bitmap.cgImage), size: hosting.bounds.size))
            scrolled.name = "XM6 scrolled advanced controls"
            scrolled.lifetime = .keepAlways
            add(scrolled)
        }
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.findScrollView(in: $0) }.first
    }
}

@MainActor
private final class XM6CompanionActivity: NotchActivity {
    let id = ActivityID("test.companion")
    let metadata = ActivityMetadata(name: "Companion", systemImage: "timer")
    @Published var livePresentationState = ActivityLivePresentationState.visible(priority: .normal)
    func makeExpandedView() -> some View { Text("Companion") }
}
