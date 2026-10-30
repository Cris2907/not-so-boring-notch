import Foundation
import Combine

/// Orchestrates the connection lifecycle, the stop-and-wait sequence-number/ACK
/// handshake, and the outbound command queue for a single Sony headset, and exposes
/// the decoded device state as `@Published` properties for SwiftUI.
///
/// Outgoing commands use one alternating bit, advanced by the device's ACK.
/// Replies and notifications are acknowledged using the complement of their own
/// incoming sequence number, independently of our outstanding outgoing command.
@MainActor
public final class HeadphonesController: ObservableObject {
    @Published public private(set) var connectionState: ConnectionState = .disconnected
    @Published public private(set) var identity = SonyDeviceIdentity()
    public let purpose: SonySessionPurpose
    public var canControlXM6: Bool { purpose == .controls && connectionState == .connected && identity.supportsXM6Controls }
    private var requestedControlState = false
    private final class Owner { weak var controller: HeadphonesController?; init(_ value: HeadphonesController) { controller = value } }
    private static var owners: [String: Owner] = [:]
    private var ownedAddress: String?
    private static func addressKey(_ address: String) -> String { address.lowercased().filter { $0.isHexDigit } }
    @Published public private(set) var deviceName: String?
    @Published public private(set) var protocolVersion: ProtocolVersion = .unknown
    @Published public private(set) var pairedDevices: [PairedDeviceInfo] = []

    @Published public private(set) var ambientSound: AmbientSoundState?
    @Published public private(set) var battery: BatteryStatus?
    @Published public private(set) var speakToChatEnabled: Bool?
    @Published public private(set) var speakToChatConfig: SpeakToChatConfigState?
    @Published public private(set) var automaticPowerOff: AutomaticPowerOffMode?
    @Published public private(set) var pauseWhenTakenOff: Bool?
    @Published public private(set) var equalizer: EqualizerState?
    @Published public private(set) var listeningMode: ListeningMode?
    @Published public private(set) var bgmRoomSize: BGMRoomSize?
    @Published public private(set) var devices: [MultipointDevice]?

    /// Raw BGM/cinema flags as last reported; listeningMode is derived from them.
    private var bgmEnabled: Bool?
    private var cinemaEnabled: Bool?
    @Published public private(set) var lastError: String?
    /// Set when the headphones connected but didn't report some state within a few
    /// seconds. The UI uses this to stop showing spinners and offer optimistic
    /// controls instead (writes still work even when the initial read was ignored).
    @Published public private(set) var initialStateTimedOut = false

    /// Persists across launches; when off, the protocol log does zero disk I/O.
    @Published public var protocolLoggingEnabled: Bool {
        didSet {
            defaults.set(protocolLoggingEnabled, forKey: "xm6.protocolLoggingEnabled")
            protocolLog.isEnabled = protocolLoggingEnabled
        }
    }

    private var connection: HeadphonesTransport?
    private let connectionFactory: () -> HeadphonesTransport
    private let pairedDevicesProvider: () -> [PairedDeviceInfo]
    private let timing: HeadphonesSessionTiming
    private let defaults: UserDefaults
    private var sessionGeneration = UUID()
    @Published public private(set) var deviceAddress: String?
    private let frameParser = FrameParser()
    private let protocolLog = ProtocolLog()

    private var sequenceNumber: UInt8 = 0
    private var outgoingQueue: [(SonyMessageType, [UInt8])] = []
    private var awaitingAck = false
    private var ackTimeoutTask: Task<Void, Never>?
    private var initRetryTask: Task<Void, Never>?
    private var stateTimeoutTask: Task<Void, Never>?
    private var connectTimeoutTask: Task<Void, Never>?
    private var equalizerWriteTask: Task<Void, Never>?
    private var initRetryCount = 0
    private var connectRetryCount = 0
    private var connectTarget: (address: String, name: String?)?
    public init(
        purpose: SonySessionPurpose = .controls,
        connectionFactory: @escaping () -> HeadphonesTransport = { RFCOMMConnection() },
        pairedDevicesProvider: @escaping () -> [PairedDeviceInfo] = { RFCOMMConnection.pairedDevices() },
        timing: HeadphonesSessionTiming = HeadphonesSessionTiming(),
        defaults: UserDefaults = .standard
    ) {
        self.purpose = purpose
        self.connectionFactory = connectionFactory
        self.pairedDevicesProvider = pairedDevicesProvider
        self.timing = timing
        self.defaults = defaults
        protocolLoggingEnabled = defaults.bool(forKey: "xm6.protocolLoggingEnabled")
        protocolLog.isEnabled = protocolLoggingEnabled
    }

    /// The path resolves inside the host app's Application Support container.
    public var protocolLogURL: URL? { protocolLog.url }

    private func closeTransport() {
        if let key = ownedAddress, Self.owners[key]?.controller === self { Self.owners[key] = nil }
        ownedAddress = nil
        sessionGeneration = UUID()
        connection?.onEvent = nil
        connection?.disconnect()
        connection = nil
    }

    private func endSession(error: String? = nil) {
        closeTransport()
        resetSessionState()
        deviceAddress = nil
        deviceName = nil
        lastError = error
        connectionState = error.map(ConnectionState.failed) ?? .disconnected
    }

    // MARK: - Public API

    public func refreshPairedDevices() {
        pairedDevices = pairedDevicesProvider()
    }

    /// Attempts to find and connect to a paired WH-1000XM6. If none is found by name,
    /// call `refreshPairedDevices()` and let the user pick manually via `connect(toAddress:)`.
    public func autoConnect() {
        refreshPairedDevices()
        if let match = pairedDevices.first(where: { $0.name.localizedCaseInsensitiveContains("WH-1000XM6") }) {
            connect(toAddress: match.id, name: match.name)
        } else {
            lastError = "Couldn't find a paired \u{201c}WH-1000XM6\u{201d}. Pair it in System Settings \u{2192} Bluetooth first, or pick it from the list below."
            connectionState = .failed(lastError ?? "")
        }
    }

    public func connect(toAddress address: String, name: String?) {
        let key = Self.addressKey(address)
        if let owner = Self.owners[key]?.controller, owner !== self {
            guard purpose == .controls && owner.purpose == .identityOnly else { return }
            owner.disconnect()
        }
        connectRetryCount = 0
        connectTarget = (address, name)
        attemptConnect()
    }

    private func attemptConnect() {
        guard let target = connectTarget else { return }
        // Tear down any live channel first; connecting on top of an open RFCOMM
        // channel leaks it and leaves two delegates fighting over one session.
        closeTransport()
        resetSessionState()
        let key = Self.addressKey(target.address)
        if let owner = Self.owners[key]?.controller, owner !== self { return }
        Self.owners[key] = Owner(self)
        ownedAddress = key
        let transport = connectionFactory()
        connection = transport
        let generation = sessionGeneration
        transport.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, self.sessionGeneration == generation else { return }
                self.handle(event)
            }
        }
        deviceAddress = target.address
        deviceName = target.name
        connectionState = .connecting
        lastError = nil
        protocolLog.startSession(deviceName: target.name)
        transport.connect(toDeviceAddress: target.address)
        startConnectTimeout()
    }

    /// Nothing in the connect path (ACL link-up, SDP query, RFCOMM channel open) is
    /// guaranteed to call back: if the headset is busy talking to a phone, or the link
    /// is half-torn-down from a previous session, IOBluetooth simply goes quiet. Without
    /// this the UI spins on "Connecting…" forever. One silent retry covers the common
    /// stale-link case; after that, say so instead of pretending we're still working.
    private func startConnectTimeout() {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.timing.connectTimeout ?? 0)
            guard let self, !Task.isCancelled else { return }
            self.handleConnectTimeout()
        }
    }

    private func handleConnectTimeout() {
        guard connectionState == .connecting || connectionState == .initializing else { return }
        guard connectRetryCount < 1 else {
            endSession(error: "The Sony control connection did not answer. Audio may still be connected. Retry to reconnect the headphone controls.")
            return
        }
        connectRetryCount += 1
        attemptConnect()
    }

    public func disconnect() {
        connectTarget = nil
        endSession()
    }

    /// Re-requests all device state (e.g. after the initial read timed out).
    public func refreshState() {
        guard canControlXM6 else { return }
        requestFullState()
    }

    // MARK: - Raw access (developer tooling)

    /// Called for every decoded inbound message; used by the XM6Probe tool.
    public var rawMessageHandler: ((SonyMessageType, [UInt8]) -> Void)?

    /// Queues a raw payload; used by the XM6Probe tool to verify command layouts.
    public func sendRaw(_ payload: [UInt8], type: SonyMessageType = .command1) {
        guard canControlXM6 else { return }
        enqueue(payload, type: type)
    }

    public func setAmbientSound(_ state: AmbientSoundState) {
        guard canControlXM6 else { return }
        ambientSound = state // optimistic; a NOTIFY will reconcile if the device disagrees
        enqueue(SonyCommands.buildAmbientSoundSet(state))
    }

    public func setSpeakToChatEnabled(_ enabled: Bool) {
        guard canControlXM6 else { return }
        speakToChatEnabled = enabled
        enqueue(SonyCommands.buildSpeakToChatEnabledSet(enabled))
    }

    public func setSpeakToChatConfig(_ config: SpeakToChatConfigState) {
        guard canControlXM6 else { return }
        speakToChatConfig = config
        enqueue(SonyCommands.buildSpeakToChatConfigSet(config))
    }

    public func setAutomaticPowerOff(_ mode: AutomaticPowerOffMode) {
        guard canControlXM6 else { return }
        automaticPowerOff = mode
        enqueue(SonyCommands.buildAutomaticPowerOffSet(mode))
    }

    public func setPauseWhenTakenOff(_ enabled: Bool) {
        guard canControlXM6 else { return }
        pauseWhenTakenOff = enabled
        enqueue(SonyCommands.buildPauseWhenTakenOffSet(enabled))
    }

    /// Writes a custom equalizer curve, coalescing rapid changes.
    ///
    /// Slider drags produce a continuous stream of values, and the protocol is
    /// stop-and-wait: one outstanding command at a time, each waiting for an ACK.
    /// Queueing every intermediate value would back the queue up for seconds after
    /// the user let go. Only the latest curve is ever in flight, so dragging stays
    /// responsive and the headphones follow within a moment of the slider settling.
    public func setEqualizerBands(_ bands: [Int]) {
        guard canControlXM6 else { return }
        guard bands.count == SonyCommands.defaultBandCount else { return }
        let bands = bands.map { min(max($0, -6), 6) }
        let subtype = equalizer?.subtype ?? 0x04
        // Optimistic, so the sliders track the drag rather than the device's replies.
        equalizer = EqualizerState(
            presetCode: EqualizerPreset.custom.rawValue,
            bands: bands,
            subtype: subtype
        )

        equalizerWriteTask?.cancel()
        equalizerWriteTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.timing.equalizerDelay ?? 0)
            guard let self, !Task.isCancelled else { return }
            self.enqueue(SonyCommands.buildEqualizerBandsSet(bands: bands, subtype: subtype))
        }
    }

    public func setEqualizerPreset(_ preset: EqualizerPreset) {
        guard canControlXM6 else { return }
        // A queued curve from a drag would otherwise land after this and drag the
        // device back to the custom preset.
        equalizerWriteTask?.cancel()
        removeQueuedEqualizerCurves()
        let subtype = equalizer?.subtype ?? 0x04
        equalizer = EqualizerState(presetCode: preset.rawValue, bands: equalizer?.bands ?? [], subtype: subtype)
        enqueue(SonyCommands.buildEqualizerPresetSet(code: preset.rawValue, subtype: subtype))
    }

    public func setListeningMode(_ mode: ListeningMode) {
        guard canControlXM6 else { return }
        listeningMode = mode
        let roomSize = bgmRoomSize ?? .middle
        enqueue(SonyCommands.buildBGMModeSet(enabled: mode == .backgroundMusic, roomSize: roomSize))
        enqueue(SonyCommands.buildUpmixCinemaSet(enabled: mode == .cinema))
    }

    public func setBGMRoomSize(_ roomSize: BGMRoomSize) {
        guard canControlXM6 else { return }
        bgmRoomSize = roomSize
        enqueue(SonyCommands.buildBGMModeSet(enabled: listeningMode == .backgroundMusic, roomSize: roomSize))
    }

    /// Switch the active playback source to another connected device.
    public func switchPlayback(to device: MultipointDevice) {
        guard canControlXM6 else { return }
        guard device.isConnected, !device.isPlayback else { return }
        guard let payload = SonyCommands.buildSourceSwitchSet(macAddress: device.macAddress) else { return }
        devices = devices?.map { d in
            var d = d
            d.isPlayback = d.macAddress == device.macAddress
            return d
        }
        enqueue(payload, type: .command2)
        // The device pushes an updated list after a switch; ask anyway as a fallback.
        enqueue(SonyCommands.buildDeviceListGet(), type: .command2)
    }

    // MARK: - Connection events

    private func resetSessionState() {
        sequenceNumber = 0
        outgoingQueue.removeAll()
        awaitingAck = false
        ackTimeoutTask?.cancel()
        initRetryTask?.cancel()
        stateTimeoutTask?.cancel()
        connectTimeoutTask?.cancel()
        equalizerWriteTask?.cancel()
        initRetryCount = 0
        initialStateTimedOut = false
        frameParser.reset()
        ambientSound = nil
        battery = nil
        speakToChatEnabled = nil
        speakToChatConfig = nil
        automaticPowerOff = nil
        pauseWhenTakenOff = nil
        equalizer = nil
        listeningMode = nil
        bgmRoomSize = nil
        devices = nil
        bgmEnabled = nil
        cinemaEnabled = nil
        protocolVersion = .unknown
        identity = SonyDeviceIdentity()
        requestedControlState = false
    }

    private func handle(_ event: RFCOMMConnectionEvent) {
        switch event {
        case .opened:
            guard connectionState == .connecting else { return }
            connectionState = .initializing
            beginHandshake()

        case .closed:
            endSession()

        case .dataReceived(let bytes):
            protocolLog.log("RX", bytes)
            for message in frameParser.feed(bytes) {
                handle(message: message)
            }

        case .failed(let message):
            endSession(error: message)
        }
    }

    private func beginHandshake() {
        initRetryCount = 0
        sendInitAttempt()
    }

    private func send(_ message: SonyMessage, note: String = "") {
        let bytes = message.encode()
        protocolLog.log("TX", bytes, note: note)
        connection?.write(bytes)
    }

    private func sendInitAttempt() {
        awaitingAck = true
        send(SonyMessage(type: .command1, sequenceNumber: sequenceNumber, payload: SonyCommands.buildInit()), note: "init")

        initRetryTask?.cancel()
        initRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.timing.handshakeTimeout ?? 0)
            guard let self, !Task.isCancelled else { return }
            self.retryInitIfNeeded()
        }
    }

    private func retryInitIfNeeded() {
        guard protocolVersion == .unknown else { return } // already got a reply
        guard initRetryCount < 2 else {
            endSession(error: "The headphones didn't respond to the connection handshake.")
            return
        }
        initRetryCount += 1
        awaitingAck = false
        sendInitAttempt()
    }

    // MARK: - Message handling

    private func handle(message: SonyMessage) {
        if message.type == .ack {
            guard awaitingAck, message.sequenceNumber != sequenceNumber else {
                return // duplicate/unexpected ACK, ignore
            }
            sequenceNumber = message.sequenceNumber
            awaitingAck = false
            ackTimeoutTask?.cancel()
            sendNextQueuedCommand()
            return
        }

        guard !message.payload.isEmpty else { return }

        // Acknowledge receipt of this command from the device. The ACK must carry the
        // complement of the *received message's* sequence number (Gadgetbridge:
        // `encodeAck` = `1 - seq` of the incoming message), NOT our own outgoing
        // sequence counter -- using the wrong one makes the headset consider its
        // replies unacknowledged and it stops responding to further requests.
        let ackSeq = message.sequenceNumber ^ 0x01
        send(SonyMessage(type: .ack, sequenceNumber: ackSeq, payload: []), note: "ack")

        rawMessageHandler?(message.type, message.payload)
        if message.type == .command1, connectionState == .connected,
           let reply = SonyIdentityProtocol.decode(message.payload) {
            var next = identity
            switch reply {
            case .modelName(let name): next.modelName = name
            case .seriesAndColor(let series, let color): next.series = series; next.color = color
            }
            identity = next
            if canControlXM6, !requestedControlState {
                requestedControlState = true
                requestFullState()
            }
            return
        }

        guard let event = SonyEventDecoder.decode(payload: message.payload, messageType: message.type) else { return }
        apply(event)
    }

    private func apply(_ event: HeadphonesEvent) {
        switch event {
        case .protocolInfo(let version):
            guard version != .unknown, connectionState == .initializing else { return }
            protocolVersion = version
            initRetryTask?.cancel()
            connectTimeoutTask?.cancel()
            connectionState = .connected
            enqueue(SonyIdentityProtocol.modelRequest)
            enqueue(SonyIdentityProtocol.colorRequest)
            if purpose == .controls { startStateTimeout() }

        case .ambientSound(let state):
            ambientSound = state
        case .battery(let status):
            battery = status
        case .speakToChatEnabled(let enabled):
            speakToChatEnabled = enabled
        case .speakToChatConfig(let config):
            speakToChatConfig = config
        case .automaticPowerOff(let mode):
            automaticPowerOff = mode
        case .pauseWhenTakenOff(let enabled):
            pauseWhenTakenOff = enabled
        case .equalizer(let state):
            equalizer = state
        case .bgmMode(let enabled, let roomSize):
            bgmEnabled = enabled
            bgmRoomSize = roomSize
            updateListeningMode()
        case .upmixCinema(let enabled):
            cinemaEnabled = enabled
            updateListeningMode()
        case .deviceList(let list):
            devices = list
        }
    }

    private func updateListeningMode() {
        if bgmEnabled == true {
            listeningMode = .backgroundMusic
        } else if cinemaEnabled == true {
            listeningMode = .cinema
        } else if bgmEnabled == false && cinemaEnabled == false {
            listeningMode = .standard
        } else {
            listeningMode = nil
        }
    }

    private func startStateTimeout() {
        stateTimeoutTask?.cancel()
        stateTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.timing.stateTimeout ?? 0)
            guard let self, !Task.isCancelled else { return }
            if self.ambientSound == nil || self.battery == nil || self.speakToChatEnabled == nil
                || self.automaticPowerOff == nil || self.pauseWhenTakenOff == nil
                || self.equalizer == nil || self.listeningMode == nil || self.devices == nil
                || self.speakToChatConfig == nil {
                self.initialStateTimedOut = true
            }
        }
    }

    private func requestFullState() {
        // Ask for ambient sound in both known v2 dialects; the device answers whichever
        // it speaks and (per the reference implementation) ignores the other.
        enqueue(SonyCommands.buildAmbientSoundGet(subtype: 0x15))
        enqueue(SonyCommands.buildAmbientSoundGet(subtype: 0x17))
        enqueue(SonyCommands.buildBatteryGet())
        enqueue(SonyCommands.buildSpeakToChatEnabledGet())
        enqueue(SonyCommands.buildSpeakToChatConfigGet())
        enqueue(SonyCommands.buildAutomaticPowerOffGet())
        enqueue(SonyCommands.buildPauseWhenTakenOffGet())
        // XM6 answers EQ inquired type 0x04; 0x00 kept as a fallback for other firmware.
        enqueue(SonyCommands.buildEqualizerGet(subtype: 0x04))
        enqueue(SonyCommands.buildEqualizerGet(subtype: 0x00))
        enqueue(SonyCommands.buildBGMModeGet())
        enqueue(SonyCommands.buildUpmixCinemaGet())
        enqueue(SonyCommands.buildDeviceListGet(), type: .command2)
    }

    // MARK: - Outbound queue

    private func removeQueuedEqualizerCurves() {
        outgoingQueue.removeAll { $0.1.first == Opcode.equalizerSet && $0.1.count > 4 }
    }

    private func enqueue(_ payload: [UInt8], type: SonyMessageType = .command1) {
        guard connectionState == .connected else { return }
        if purpose == .identityOnly, type != .command1 || (payload != SonyIdentityProtocol.modelRequest && payload != SonyIdentityProtocol.colorRequest) { return }
        if payload.first == Opcode.equalizerSet, payload.count > 4 {
            removeQueuedEqualizerCurves()
        }
        outgoingQueue.append((type, payload))
        if !awaitingAck {
            sendNextQueuedCommand()
        }
    }

    private func sendNextQueuedCommand() {
        guard connectionState == .connected, !outgoingQueue.isEmpty else { return }
        let (type, payload) = outgoingQueue.removeFirst()
        awaitingAck = true
        send(SonyMessage(type: type, sequenceNumber: sequenceNumber, payload: payload))

        ackTimeoutTask?.cancel()
        ackTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.timing.ackTimeout ?? 0)
            guard let self, !Task.isCancelled else { return }
            self.handleAckTimeout()
        }
    }

    private func handleAckTimeout() {
        guard awaitingAck else { return }
        endSession(error: "The headphones stopped acknowledging commands. Try connecting again.")
    }
}
