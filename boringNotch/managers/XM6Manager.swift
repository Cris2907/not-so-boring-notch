import AppKit
import Combine
// Legacy delegate objects have no Sendable annotations; all monitor state and
// delegate-object access is serialized onto the main queue below.
@preconcurrency import IOBluetooth
import SonyHeadphonesKit

@MainActor
protocol XM6ConnectionMonitoring: AnyObject {
    var onWake: (() -> Void)? { get set }
    var onSleep: (() -> Void)? { get set }
    var onConnect: ((String) -> Void)? { get set }
    var onDisconnect: ((String) -> Void)? { get set }
    func start()
    func stop()
}

/// Independent of headphone-notification preferences and the selected audio output:
/// a multipoint XM6 can be controlled while another device is playing audio.
@MainActor
final class XM6ConnectionMonitor: NSObject, XM6ConnectionMonitoring {
    var onWake: (() -> Void)?
    var onSleep: (() -> Void)?
    var onConnect: ((String) -> Void)?
    var onDisconnect: ((String) -> Void)?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(deviceConnected(_:device:))
        )
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.onWake?() }
            },
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.onSleep?() }
            }
        ]
        for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [] where device.isConnected() {
            watchDisconnect(device)
        }
    }

    func stop() {
        isStarted = false
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
    }

    private func watchDisconnect(_ device: IOBluetoothDevice) {
        guard let address = device.addressString, disconnectNotifications[address] == nil else { return }
        disconnectNotifications[address] = device.register(
            forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:))
        )
    }

    @objc nonisolated private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isStarted, notification === self.connectNotification,
                  let address = device.addressString else { return }
            self.watchDisconnect(device)
            self.onConnect?(address)
        }
    }

    @objc nonisolated private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isStarted, let address = device.addressString,
                  notification === self.disconnectNotifications[address] else { return }
            self.disconnectNotifications.removeValue(forKey: address)?.unregister()
            self.onDisconnect?(address)
        }
    }
}

@MainActor
final class XM6Manager: ObservableObject {
    static let shared = XM6Manager()

    let controller: HeadphonesController
    @Published var automaticReconnect: Bool {
        didSet {
            defaults.set(automaticReconnect, forKey: "xm6.automaticReconnect")
            if automaticReconnect { reconnectIfNeeded() }
        }
    }
    @Published private(set) var rememberedDevice: PairedDeviceInfo?
    @Published private(set) var defaultDevice: PairedDeviceInfo?
    @Published private(set) var isEnabled = true
    @Published private(set) var isStarted = false
    private(set) var manuallyDisconnected = false
    private var sleeping = false
    private var attemptedDevice: PairedDeviceInfo?
    private let defaults: UserDefaults
    private let enablement: ActivityEnablementStore
    private let monitor: XM6ConnectionMonitoring
    private var observations: Set<AnyCancellable> = []

    init(
        controller: HeadphonesController? = nil,
        defaults: UserDefaults = .standard,
        enablement: ActivityEnablementStore? = nil,
        monitor: XM6ConnectionMonitoring? = nil
    ) {
        self.defaults = defaults
        self.controller = controller ?? HeadphonesController(defaults: defaults)
        self.enablement = enablement ?? .shared
        self.monitor = monitor ?? XM6ConnectionMonitor()
        automaticReconnect = defaults.object(forKey: "xm6.automaticReconnect") as? Bool ?? true
        if let address = defaults.string(forKey: "xm6.deviceAddress") {
            rememberedDevice = PairedDeviceInfo(id: address, name: defaults.string(forKey: "xm6.deviceName") ?? "WH-1000XM6")
        }
        if let address = defaults.string(forKey: "xm6.defaultDeviceAddress") {
            defaultDevice = PairedDeviceInfo(id: address, name: defaults.string(forKey: "xm6.defaultDeviceName") ?? "WH-1000XM6")
        }
        self.controller.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &observations)
        self.controller.$connectionState.dropFirst().sink { [weak self] state in
            guard let self, state == .connected, let address = self.controller.deviceAddress else { return }
            let device = PairedDeviceInfo(id: address, name: self.controller.deviceName ?? "WH-1000XM6")
            self.rememberedDevice = device
            self.defaults.set(device.id, forKey: "xm6.deviceAddress")
            self.defaults.set(device.name, forKey: "xm6.deviceName")
            if self.isStarted, self.isEnabled { self.monitor.start() }
        }.store(in: &observations)
        self.enablement.$disabledActivityIDs.sink { [weak self] disabled in
            self?.setEnabled(!disabled.contains(.xm6))
        }.store(in: &observations)
        self.monitor.onWake = { [weak self] in
            self?.sleeping = false
            self?.reconnectIfNeeded()
        }
        self.monitor.onSleep = { [weak self] in
            self?.sleeping = true
            self?.controller.disconnect()
        }
        self.monitor.onConnect = { [weak self] address in
            guard let self, self.preferredDevice?.id.caseInsensitiveCompare(address) == .orderedSame else { return }
            self.reconnectIfNeeded()
        }
        self.monitor.onDisconnect = { [weak self] address in
            guard let self, self.controller.deviceAddress?.caseInsensitiveCompare(address) == .orderedSame else { return }
            self.controller.disconnect()
        }
    }

    var isConnected: Bool { controller.connectionState == .connected }
    var isConnecting: Bool {
        controller.connectionState == .connecting || controller.connectionState == .initializing
    }
    private var preferredDevice: PairedDeviceInfo? { defaultDevice ?? rememberedDevice }

    /// An explicit default is saved immediately, independently of the last
    /// successful connection. Choosing another device once does not replace it.
    func setDefaultDevice(_ device: PairedDeviceInfo?) {
        guard defaultDevice != device else { return }
        defaultDevice = device
        defaults.set(device?.id, forKey: "xm6.defaultDeviceAddress")
        defaults.set(device?.name, forKey: "xm6.defaultDeviceName")
        attemptedDevice = nil
        guard isStarted, isEnabled else { return }
        if preferredDevice != nil {
            monitor.start()
        } else if !isConnected && !isConnecting {
            monitor.stop()
        }
        reconnectIfNeeded()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        manuallyDisconnected = false
        sleeping = false
        if isEnabled {
            if preferredDevice != nil { monitor.start() }
            reconnectIfNeeded()
        }
    }

    func stop() {
        isStarted = false
        monitor.stop()
        controller.disconnect()
    }

    private func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        guard isStarted else { return }
        if enabled {
            if preferredDevice != nil { monitor.start() }
            reconnectIfNeeded()
        } else {
            monitor.stop()
            controller.disconnect()
        }
    }

    func connect(to device: PairedDeviceInfo? = nil) {
        guard isStarted, isEnabled, !sleeping, !isConnecting else { return }
        manuallyDisconnected = false
        if let target = device ?? defaultDevice ?? attemptedDevice ?? rememberedDevice {
            attemptedDevice = target
            controller.connect(toAddress: target.id, name: target.name)
        } else {
            controller.autoConnect()
        }
    }

    func disconnect() {
        manuallyDisconnected = true
        controller.disconnect()
    }

    private func reconnectIfNeeded() {
        guard isStarted, isEnabled, automaticReconnect, !manuallyDisconnected,
              !sleeping, !isConnected, !isConnecting, let device = preferredDevice else { return }
        controller.connect(toAddress: device.id, name: device.name)
    }
}
