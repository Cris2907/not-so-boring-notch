import AppKit
import Combine
import CoreAudio
import Defaults
import Foundation
import IOBluetooth
import IOKit.audio

final class BluetoothAudioManager: NSObject, ObservableObject {
    static let shared = BluetoothAudioManager()

    @Published private(set) var currentOutputDevice: BluetoothAudioDevice?
    @Published private(set) var activeNotificationDevice: BluetoothAudioDevice?
    @Published private(set) var activeProfile: BluetoothHeadphoneProfile = BluetoothHeadphoneProfileStore.fallbackProfile

    private var assignmentObservation: AnyCancellable?
    private var artworkObservation: AnyCancellable?
    private var notificationPresented = false
    private var notificationHasAnimatedDuration = false

    private var isStarted = false
    private var audioListenersInstalled = false
    private var didInitialFetch = false
    private var lastSeenOutputSignature: String?
    private var lastNotifiedSignature: String?
    private var lastNotificationDate: Date = .distantPast
    private var refreshWorkItem: DispatchWorkItem?
    private var clearNotificationWorkItem: DispatchWorkItem?
    private var bluetoothConnectNotification: IOBluetoothUserNotification?
    private var bluetoothDisconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    private override init() {
        super.init()
        assignmentObservation = HeadphoneModelAssignments.shared.$assignments
            .receive(on: DispatchQueue.main)
            .sink { [weak self] assignments in
                guard let self, let device = self.activeNotificationDevice else { return }
                // Update an existing notification without restarting its animation or timeout.
                self.activeProfile = BluetoothHeadphoneProfileStore.profile(for: device, assignments: assignments)
            }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        Task { @MainActor [weak self] in
            guard let self, self.isStarted else { return }
            SonyDeviceIdentityStore.shared.start(audio: self, controls: XM6Manager.shared.controller)
            self.artworkObservation = SonyArtworkStore.shared.$files.receive(on: DispatchQueue.main).sink { [weak self] _ in
                Task { @MainActor in self?.refreshSonyNotificationProfile() }
            }
        }

        installAudioListenersIfNeeded()
        installBluetoothNotificationsIfNeeded()
        refreshCurrentOutput(triggerNotification: false)
    }

    func stop() {
        isStarted = false
        artworkObservation = nil
        notificationPresented = false
        Task { @MainActor in SonyDeviceIdentityStore.shared.stop() }
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        clearNotificationWorkItem?.cancel()
        clearNotificationWorkItem = nil
        bluetoothConnectNotification?.unregister()
        bluetoothConnectNotification = nil
        bluetoothDisconnectNotifications.values.forEach { $0.unregister() }
        bluetoothDisconnectNotifications.removeAll()
    }

    private func installAudioListenersIfNeeded() {
        guard !audioListenersInstalled else { return }
        audioListenersInstalled = true

        var defaultOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.refreshCurrentOutput(triggerNotification: true)
        }

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.scheduleOutputRefresh()
        }
    }

    private func installBluetoothNotificationsIfNeeded() {
        guard bluetoothConnectNotification == nil, Defaults[.useBluetoothDeviceMatching] else { return }
        bluetoothConnectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(bluetoothDeviceConnected(_:device:))
        )
    }

    private func scheduleOutputRefresh() {
        refreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.refreshCurrentOutput(triggerNotification: true)
        }
        refreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func refreshCurrentOutput(triggerNotification: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.refreshCurrentOutput(triggerNotification: triggerNotification)
            }
            return
        }
        guard isStarted else { return }

        let outputDeviceID = systemOutputDeviceID()
        guard outputDeviceID != kAudioObjectUnknown,
              let audioDevice = makeAudioDevice(from: outputDeviceID)
        else {
            currentOutputDevice = nil
            return
        }

        let enrichedDevice = enrichWithBluetoothMetadata(audioDevice)
        let currentSignature = signature(for: enrichedDevice)
        let outputChanged = currentSignature != lastSeenOutputSignature
        lastSeenOutputSignature = currentSignature
        currentOutputDevice = enrichedDevice

        guard didInitialFetch else {
            didInitialFetch = true
            return
        }

        guard triggerNotification || outputChanged else { return }
        guard outputChanged else { return }
        guard Defaults[.showBluetoothHeadphoneNotifications], enrichedDevice.isBluetooth else { return }

        notifyDeviceBecameActive(enrichedDevice)
    }

    private func notifyDeviceBecameActive(_ device: BluetoothAudioDevice) {
        let deviceSignature = signature(for: device)
        let now = Date()

        if lastNotifiedSignature == deviceSignature,
           now.timeIntervalSince(lastNotificationDate) < 10 {
            return
        }

        lastNotifiedSignature = deviceSignature
        lastNotificationDate = now

        notificationPresented = false
        notificationHasAnimatedDuration = false
        activeNotificationDevice = device
        activeProfile = HeadphoneModelAssignments.shared.profile(for: device)
        Task { @MainActor [weak self] in
            guard let self, self.activeNotificationDevice == device else { return }
            self.refreshSonyNotificationProfile()
            let profile = self.activeProfile
            let entry = SonyDeviceIdentityStore.shared.artworkEntry(address: device.bluetoothAddress, profile: profile)
            let hasAnimation = SonyArtworkStore.shared.localFile(for: entry?.animationURL) != nil
            let animated = hasAnimation && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            self.notificationPresented = true
            self.notificationHasAnimatedDuration = animated
            self.presentBluetoothNotification(duration: animated ? 5.5 : 2.5, profile: profile)

        }
    }

    @MainActor
    func refreshSonyNotificationProfile() {
        guard let device = activeNotificationDevice else { return }
        activeProfile = SonyDeviceIdentityStore.shared.profile(for: device)
        // Extend only a still-visible notification when its first render becomes ready.
        // Never resurrect an expired notification or restart its animation on state updates.
        let coordinator = BoringViewCoordinator.shared
        if notificationPresented, !notificationHasAnimatedDuration,
           coordinator.sneakPeek.show, coordinator.sneakPeek.type == .bluetooth,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
           let entry = SonyDeviceIdentityStore.shared.artworkEntry(address: device.bluetoothAddress, profile: activeProfile),
           SonyArtworkStore.shared.localFile(for: entry.animationURL) != nil {
            if coordinator.extendBluetoothSneakPeek(duration: 5.5) {
                notificationHasAnimatedDuration = true
                scheduleBluetoothNotificationClear(after: 6.0)
            }
        }
    }

    @MainActor
    private func presentBluetoothNotification(duration: TimeInterval, profile: BluetoothHeadphoneProfile) {
        BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .bluetooth, duration: duration, icon: profile.symbolName)
        scheduleBluetoothNotificationClear(after: duration + 0.5)
    }

    private func scheduleBluetoothNotificationClear(after duration: TimeInterval) {
        clearNotificationWorkItem?.cancel()
        let clear = DispatchWorkItem { [weak self] in
            self?.notificationPresented = false
            self?.activeNotificationDevice = nil
            self?.activeProfile = BluetoothHeadphoneProfileStore.fallbackProfile
        }
        clearNotificationWorkItem = clear
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: clear)
    }

    private func makeAudioDevice(from deviceID: AudioObjectID) -> BluetoothAudioDevice? {
        let name = readStringProperty(
            deviceID: deviceID,
            selector: kAudioObjectPropertyName,
            scope: kAudioObjectPropertyScopeGlobal
        ) ?? readStringProperty(
            deviceID: deviceID,
            selector: kAudioObjectPropertyName,
            scope: kAudioDevicePropertyScopeOutput
        )

        guard let name else { return nil }

        let transportType = readUInt32Property(
            deviceID: deviceID,
            selector: kAudioDevicePropertyTransportType,
            scope: kAudioObjectPropertyScopeGlobal
        ) ?? 0

        let manufacturer = readStringProperty(
            deviceID: deviceID,
            selector: kAudioObjectPropertyManufacturer,
            scope: kAudioObjectPropertyScopeGlobal
        )

        let modelUID = readStringProperty(
            deviceID: deviceID,
            selector: kAudioDevicePropertyModelUID,
            scope: kAudioObjectPropertyScopeGlobal
        )

        let deviceUID = readStringProperty(
            deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID,
            scope: kAudioObjectPropertyScopeGlobal
        )
        let address = BluetoothAddress.fromDeviceUID(deviceUID)

        return BluetoothAudioDevice(
            audioObjectID: deviceID,
            name: name,
            manufacturer: manufacturer,
            modelUID: modelUID,
            transportType: transportType,
            bluetoothAddress: address,
            isBluetooth: transportType == UInt32(kIOAudioDeviceTransportTypeBluetooth)
                || (transportType == UInt32(kIOAudioDeviceTransportTypeWireless) && address != nil),
            detectedAt: Date()
        )
    }

    private func enrichWithBluetoothMetadata(_ audioDevice: BluetoothAudioDevice) -> BluetoothAudioDevice {
        guard Defaults[.useBluetoothDeviceMatching],
              let bluetoothDevice = matchingBluetoothDevice(for: audioDevice)
        else {
            return audioDevice
        }

        registerDisconnectNotification(for: bluetoothDevice)

        return BluetoothAudioDevice(
            audioObjectID: audioDevice.audioObjectID,
            name: audioDevice.name,
            manufacturer: audioDevice.manufacturer,
            modelUID: audioDevice.modelUID,
            transportType: audioDevice.transportType,
            bluetoothAddress: BluetoothAddress.canonical(bluetoothDevice.addressString),
            isBluetooth: audioDevice.isBluetooth || audioDevice.transportType == UInt32(kIOAudioDeviceTransportTypeWireless),
            detectedAt: audioDevice.detectedAt
        )
    }

    static func pairedHeadphones() -> [PairedHeadphoneIdentity] {
        ((IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []).compactMap { device in
            guard let address = BluetoothAddress.canonical(device.addressString) else { return nil }
            return PairedHeadphoneIdentity(address: address, name: device.name ?? device.addressString ?? address,
                                           isConnected: device.isConnected())
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func matchingBluetoothDevice(for audioDevice: BluetoothAudioDevice) -> IOBluetoothDevice? {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let identities = devices.compactMap { device -> PairedHeadphoneIdentity? in
            guard let address = BluetoothAddress.canonical(device.addressString) else { return nil }
            return PairedHeadphoneIdentity(address: address, name: device.name ?? "", isConnected: device.isConnected())
        }
        guard let identity = BluetoothHeadphoneAssociation.match(
            address: audioDevice.bluetoothAddress, name: audioDevice.name, devices: identities
        ) else { return nil }
        return devices.first { BluetoothAddress.canonical($0.addressString) == identity.address }
    }

    private func registerDisconnectNotification(for device: IOBluetoothDevice) {
        guard let address = device.addressString,
              bluetoothDisconnectNotifications[address] == nil
        else { return }

        bluetoothDisconnectNotifications[address] = device.register(
            forDisconnectNotification: self,
            selector: #selector(bluetoothDeviceDisconnected(_:device:))
        )
    }

    @objc private func bluetoothDeviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { [weak self] in
            self?.registerDisconnectNotification(for: device)
            self?.scheduleOutputRefresh()
        }
    }

    @objc private func bluetoothDeviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { [weak self] in
            if let address = device.addressString {
                self?.bluetoothDisconnectNotifications[address]?.unregister()
                self?.bluetoothDisconnectNotifications.removeValue(forKey: address)
            }
            self?.scheduleOutputRefresh()
        }
    }

    private func systemOutputDeviceID() -> AudioObjectID {
        var defaultDeviceID = kAudioObjectUnknown
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &defaultDeviceID
        )
        return status == noErr ? defaultDeviceID : kAudioObjectUnknown
    }

    private func readStringProperty(
        deviceID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &propertyAddress) else { return nil }

        var value: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &value
        )
        guard status == noErr else { return nil }
        return value as String?
    }

    private func readUInt32Property(
        deviceID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> UInt32? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &propertyAddress) else { return nil }

        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &value
        )
        return status == noErr ? value : nil
    }

    private func signature(for device: BluetoothAudioDevice) -> String {
        [
            String(device.audioObjectID),
            BluetoothHeadphoneProfileStore.normalize(device.name),
            BluetoothHeadphoneProfileStore.normalize(device.modelUID),
            BluetoothHeadphoneProfileStore.normalize(device.bluetoothAddress),
            String(device.transportType)
        ].joined(separator: "|")
    }
}