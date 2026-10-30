import AppKit
import Combine
import Defaults
import IOBluetooth
import SonyHeadphonesKit

/// Identity is scoped to a Bluetooth address, never the editable audio-device name.
@MainActor
final class SonyDeviceIdentityStore: ObservableObject {
    static let shared = SonyDeviceIdentityStore()
    @Published private(set) var identities: [String: SonyDeviceIdentity] = [:]
    @Published private(set) var activeDevice: BluetoothAudioDevice?
    let catalog: SonyArtworkCatalog
    private let assignments: HeadphoneModelAssignments
    private let loadArtwork: @MainActor (SonyArtworkEntry) -> Void
    init(catalog: SonyArtworkCatalog = .init(), assignments: HeadphoneModelAssignments = .shared,
         loadArtwork: @escaping @MainActor (SonyArtworkEntry) -> Void = { SonyArtworkStore.shared.load($0) }) {
        self.catalog = catalog; self.assignments = assignments; self.loadArtwork = loadArtwork
    }
    private weak var audio: BluetoothAudioManager?
    private weak var controls: HeadphonesController?
    private var subscriptions = Set<AnyCancellable>()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var probe: HeadphonesController?
    private var probeObservation: AnyCancellable?
    private var deadline: Task<Void, Never>?
    private var target: String?
    private var attempted: String?
    private var sleeping = false

    func start(audio: BluetoothAudioManager, controls: HeadphonesController) {
        guard self.audio == nil else { return }
        self.audio = audio; self.controls = controls
        Defaults.publisher(.useBluetoothDeviceMatching).receive(on: DispatchQueue.main).sink { [weak self] _ in self?.synchronize() }.store(in: &subscriptions)
        audio.$currentOutputDevice.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.synchronize() }.store(in: &subscriptions)
        controls.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] in self?.synchronize() }.store(in: &subscriptions)
        assignments.$assignments.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.sleeping = true; self?.cancelProbe(); self?.identities = [:]; self?.activeDevice = nil; self?.attempted = nil }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.sleeping = false; self?.synchronize() }
            }
        ]
        synchronize()
    }
    func stop() {
        cancelProbe(); subscriptions.removeAll()
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers = []; audio = nil; controls = nil; identities = [:]; activeDevice = nil; target = nil; attempted = nil
    }
    func disconnected(_ address: String?) {
        guard let address = BluetoothAddress.canonical(address) else { return }
        identities[address] = nil
        if target == address { cancelProbe(); attempted = nil }
    }
    func identity(for address: String?) -> SonyDeviceIdentity? {
        BluetoothAddress.canonical(address).flatMap { identities[$0] }
    }
    func profile(for device: BluetoothAudioDevice) -> BluetoothHeadphoneProfile {
        if assignments.assignedProfileID(for: device.bluetoothAddress) != nil { return assignments.profile(for: device) }
        guard let model = identity(for: device.bluetoothAddress)?.modelName else { return assignments.profile(for: device) }
        return BluetoothHeadphoneProfileStore.sonyProfiles.first { $0.displayName == "Sony " + model }
            ?? BluetoothHeadphoneProfile(id: "sony-" + model.lowercased(), displayName: "Sony " + model, modelKeys: [model], manufacturerKeys: ["sony"])
    }
    func artworkEntry(address: String?, profile: BluetoothHeadphoneProfile) -> SonyArtworkEntry? {
        let identity = identity(for: address)
        let assigned = assignments.assignedProfileID(for: address) != nil
        let model = assigned ? profile.displayName.replacingOccurrences(of: "Sony ", with: "")
            : identity?.modelName ?? profile.displayName.replacingOccurrences(of: "Sony ", with: "")
        let color = identity?.modelName == model ? identity?.color : nil
        return catalog.entry(model: model, color: color)
    }
    func record(_ identity: SonyDeviceIdentity, address: String) {
        guard let address = BluetoothAddress.canonical(address), identity.modelName != nil else { return }
        if identities[address] != identity { identities[address] = identity }
        if let entry = catalog.entry(model: identity.modelName!, color: identity.color) { loadArtwork(entry) }
        audio?.refreshSonyNotificationProfile()
    }
    private func synchronize() {
        guard !sleeping else { return }
        activeDevice = audio?.currentOutputDevice
        if let controls, let address = BluetoothAddress.canonical(controls.deviceAddress), controls.connectionState == .connected {
            record(controls.identity, address: address)
        }
        let next = Defaults[.useBluetoothDeviceMatching] ? audio?.currentOutputDevice.flatMap { $0.isBluetooth ? BluetoothAddress.canonical($0.bluetoothAddress) : nil } : nil
        if next != target { cancelProbe(); target = next; attempted = nil }
        guard let address = target, let device = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice])?.first(where: {
            BluetoothAddress.canonical($0.addressString) == address && $0.isConnected()
        }) else { return }
        if BluetoothAddress.canonical(controls?.deviceAddress) == address {
            cancelProbe() // The controls session performs its own identity inquiries.
            return
        }
        guard attempted != address else { return }
        attempted = address
        let controller = HeadphonesController(purpose: .identityOnly,
            connectionFactory: { RFCOMMConnection(requiresExistingConnection: true) })
        probe = controller
        probeObservation = controller.$identity.receive(on: DispatchQueue.main).sink { [weak self, weak controller] identity in
            guard let self, let controller, self.probe === controller, self.target == address else { return }
            self.record(identity, address: address)
            if identity.isComplete { self.cancelProbe() }
        }
        controller.connect(toAddress: device.addressString, name: device.name)
        deadline = Task { [weak self, weak controller] in
            do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
            guard let self, self.probe === controller else { return }
            self.cancelProbe()
        }
    }
    private func cancelProbe() {
        deadline?.cancel(); deadline = nil; probeObservation = nil
        probe?.disconnect(); probe = nil
    }
}
