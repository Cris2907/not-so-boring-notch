import XCTest
@testable import SonyHeadphonesKit

final class TestTransport: HeadphonesTransport {
    var onEvent: ((RFCOMMConnectionEvent) -> Void)?
    var addresses: [String] = []
    var disconnected = false
    var messages: [SonyMessage] = []
    var acknowledgeWrites = true
    func connect(toDeviceAddress address: String) { addresses.append(address) }
    func disconnect() { disconnected = true }
    func write(_ bytes: [UInt8]) {
        guard let message = SonyMessage.decode(rawFrame: bytes) else { return }
        messages.append(message)
        if acknowledgeWrites, message.type != .ack {
            emit([], type: .ack, sequence: message.sequenceNumber ^ 1)
        }
    }
    func emit(_ payload: [UInt8], type: SonyMessageType = .command1, sequence: UInt8 = 0) {
        onEvent?(.dataReceived(SonyMessage(type: type, sequenceNumber: sequence, payload: payload).encode()))
    }
    var commands: [SonyMessage] { messages.filter { $0.type != .ack } }
}

@MainActor
final class HeadphonesControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        super.setUp()
        suite = "XM6KitTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func settle() async {
        for _ in 0..<40 { await Task.yield() }
    }

    private func connected(_ transport: TestTransport, timing: HeadphonesSessionTiming = .init()) async -> HeadphonesController {
        let controller = HeadphonesController(connectionFactory: { transport }, pairedDevicesProvider: { [] }, timing: timing, defaults: defaults)
        controller.connect(toAddress: "AA-BB", name: "XM6")
        transport.onEvent?(.opened)
        await settle()
        transport.emit([0x01, 0, 0, 0, 0, 0, 0, 0])
        await settle()
        XCTAssertEqual(controller.connectionState, .connected)
        return controller
    }

    func testInitializationReadsStateWithoutChangingOffOrZeroAmbient() async {
        let transport = TestTransport()
        let controller = await connected(transport)
        transport.emit([0x67, 0x15, 1, 0, 0, 1, 0])
        await settle()
        XCTAssertEqual(controller.ambientSound?.mode, .off)
        XCTAssertEqual(controller.ambientSound?.level, 0)
        XCTAssertEqual(controller.ambientSound?.focusOnVoice, true)
        let reads: Set<UInt8> = [0, 0x66, 0x22, 0xf6, 0xfa, 0x26, 0x56, 0xe6, 0x36]
        XCTAssertTrue(transport.commands.allSatisfy { reads.contains($0.payload[0]) })
        XCTAssertEqual(transport.commands.count, 13) // handshake plus twelve queries
        controller.disconnect()
    }

    func testExternalReportsPersonalizedEQAndChargingAreMirrored() async {
        let transport = TestTransport()
        let controller = await connected(transport)
        transport.emit([0x25, 0, 100, 1])
        transport.emit([0x59, 4, 0x91, 0])
        transport.emit([0x69, 0x15, 1, 1, 1, 1, 7])
        await settle()
        XCTAssertEqual(controller.battery, BatteryStatus(level: 100, isCharging: true))
        XCTAssertEqual(controller.equalizer?.presetCode, 0x91)
        XCTAssertNil(controller.equalizer?.preset)
        XCTAssertEqual(controller.ambientSound?.mode, .ambientSound)
        XCTAssertEqual(controller.ambientSound?.level, 7)
        controller.disconnect()
    }

    func testCommandsHaveExpectedWirePayloadsAndTable() async {
        let transport = TestTransport()
        let controller = await connected(transport)
        transport.messages.removeAll()
        controller.setAmbientSound(.init(mode: .ambientSound, focusOnVoice: true, level: 20))
        controller.setSpeakToChatEnabled(true)
        controller.setSpeakToChatConfig(.init(sensitivity: .high, timeout: .long))
        controller.setAutomaticPowerOff(.whenTakenOff)
        controller.setPauseWhenTakenOff(true)
        controller.setListeningMode(.cinema)
        controller.setBGMRoomSize(.large)
        controller.setEqualizerPreset(.clear)
        controller.switchPlayback(to: .init(macAddress: "AA:BB:CC:DD:EE:FF", name: "Mac", connectedStatus: 2, isPlayback: false))
        await settle()
        let payloads = transport.commands.map(\.payload)
        XCTAssertEqual(Array(payloads.prefix(6)), [
            [0x68, 0x15, 1, 1, 1, 1, 20], [0xf8, 0x0c, 0, 1],
            [0xfc, 0x0c, 1, 2], [0x28, 5, 0x10, 0], [0xf8, 1, 0], [0xe8, 9, 1, 1]
        ])
        XCTAssertTrue(payloads.contains([0xe8, 4, 0]))
        XCTAssertTrue(payloads.contains([0xe8, 9, 1, 2]))
        XCTAssertTrue(payloads.contains([0x58, 4, 0x31, 0]))
        XCTAssertEqual(transport.commands.suffix(2).map(\.type), [.command2, .command2])
        XCTAssertEqual(transport.commands.dropLast().last?.payload, [0x3c, 1] + Array("AA:BB:CC:DD:EE:FF".utf8))
        controller.disconnect()
    }

    func testEqualizerCoalescesClampsAndPresetCancelsDelayedCurve() async throws {
        let transport = TestTransport()
        let controller = await connected(transport, timing: .init(equalizerDelay: 10_000_000))
        transport.messages.removeAll()
        controller.setEqualizerBands(Array(repeating: 2, count: 10))
        controller.setEqualizerBands(Array(repeating: 99, count: 10))
        try await Task.sleep(nanoseconds: 40_000_000)
        await settle()
        XCTAssertEqual(transport.commands.map(\.payload), [[0x58, 4, 0xa0, 10] + Array(repeating: 12, count: 10)])
        controller.setEqualizerBands(Array(repeating: -2, count: 10))
        controller.setEqualizerPreset(.soft)
        try await Task.sleep(nanoseconds: 40_000_000)
        await settle()
        XCTAssertEqual(transport.commands.count, 2)
        XCTAssertEqual(transport.commands.last?.payload, [0x58, 4, 0x33, 0])
        controller.disconnect()
    }

    func testDisconnectAndFailureClearStateAndPendingWrites() async throws {
        let transport = TestTransport()
        let controller = await connected(transport, timing: .init(equalizerDelay: 10_000_000))
        transport.emit([0x25, 0, 50, 0])
        await settle()
        controller.setEqualizerBands(Array(repeating: 3, count: 10))
        transport.messages.removeAll()
        let abandonedCallback = transport.onEvent
        controller.disconnect()
        abandonedCallback?(.opened)
        abandonedCallback?(.dataReceived(SonyMessage(type: .command1, sequenceNumber: 0, payload: [0x25, 0, 90, 0]).encode()))
        controller.setSpeakToChatEnabled(true)
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertEqual(controller.connectionState, .disconnected)
        XCTAssertNil(controller.battery)
        XCTAssertNil(controller.equalizer)
        XCTAssertNil(controller.deviceAddress)
        XCTAssertTrue(transport.commands.isEmpty)
        XCTAssertTrue(transport.disconnected)
    }

    func testOldSessionEventsCannotAffectReplacementSession() async {
        var transports: [TestTransport] = []
        let controller = HeadphonesController(connectionFactory: {
            let transport = TestTransport(); transports.append(transport); return transport
        }, defaults: defaults)
        controller.connect(toAddress: "first", name: "First")
        let oldCallback = transports[0].onEvent
        controller.connect(toAddress: "second", name: "Second")
        oldCallback?(.failed("stale failure"))
        oldCallback?(.closed)
        oldCallback?(.opened)
        await settle()
        XCTAssertEqual(controller.connectionState, .connecting)
        XCTAssertEqual(controller.deviceAddress, "second")
        XCTAssertTrue(transports[0].disconnected)
        XCTAssertTrue(transports[1].messages.isEmpty)
        controller.disconnect()
    }

    func testUnexpectedClosureAndFailureClearReportedState() async {
        for event in [RFCOMMConnectionEvent.closed, .failed("Bluetooth permission denied")] {
            let transport = TestTransport()
            let controller = await connected(transport)
            transport.emit([0x25, 0, 75, 0])
            transport.emit([0x69, 0x15, 1, 1, 0, 0, 5])
            await settle()
            XCTAssertNotNil(controller.battery)
            transport.onEvent?(event)
            await settle()
            XCTAssertNil(controller.battery)
            XCTAssertNil(controller.ambientSound)
            XCTAssertNil(controller.deviceName)
            XCTAssertTrue(transport.disconnected)
            XCTAssertNotEqual(controller.connectionState, .connected)
            controller.disconnect()
        }
    }

    func testMissingACKEndsSessionAndCancelsQueue() async throws {
        let transport = TestTransport()
        let controller = await connected(transport, timing: .init(ackTimeout: 10_000_000))
        transport.messages.removeAll()
        transport.acknowledgeWrites = false
        controller.setSpeakToChatEnabled(true)
        controller.setPauseWhenTakenOff(true)
        try await Task.sleep(nanoseconds: 35_000_000)
        guard case .failed = controller.connectionState else { return XCTFail("Expected missing-ACK failure") }
        XCTAssertEqual(transport.commands.count, 1)
        XCTAssertNil(controller.speakToChatEnabled)
        XCTAssertTrue(transport.disconnected)
        controller.disconnect()
    }

    func testListeningModeDoesNotInventStandardFromPartialReports() async {
        let transport = TestTransport()
        let controller = await connected(transport)
        transport.emit([0xe9, 9, 1, 1]) // BGM off; cinema still unknown
        await settle()
        XCTAssertNil(controller.listeningMode)
        transport.emit([0xe9, 4, 1])
        await settle()
        XCTAssertEqual(controller.listeningMode, .standard)
        transport.emit([0xe9, 4, 0])
        await settle()
        XCTAssertEqual(controller.listeningMode, .cinema)
        controller.disconnect()
    }

    func testSilentConnectionRetriesOnceAndStops() async throws {
        var attempts = 0
        let controller = HeadphonesController(connectionFactory: {
            attempts += 1; return TestTransport()
        }, timing: .init(connectTimeout: 10_000_000), defaults: defaults)
        controller.connect(toAddress: "XM6", name: "XM6")
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(attempts, 2)
        guard case .failed = controller.connectionState else { return XCTFail("Expected bounded connection failure") }
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(attempts, 2)
        controller.disconnect()
    }

    func testPartialStateTimeoutAndRefreshRemainReadOnly() async throws {
        let transport = TestTransport()
        let controller = await connected(transport, timing: .init(stateTimeout: 10_000_000))
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(controller.initialStateTimedOut)
        XCTAssertNil(controller.battery)
        XCTAssertNil(controller.ambientSound)
        transport.messages.removeAll()
        controller.refreshState()
        await settle()
        XCTAssertEqual(transport.commands.count, 12)
        XCTAssertFalse(transport.commands.contains { $0.payload.first == 0x68 })
        controller.disconnect()
    }

    func testMalformedFramesAndUnknownProtocolCannotConnect() async {
        let transport = TestTransport()
        let controller = HeadphonesController(connectionFactory: { transport }, defaults: defaults)
        controller.connect(toAddress: "XM6", name: "XM6")
        transport.onEvent?(.opened)
        await settle()
        transport.onEvent?(.dataReceived([0x3e, 1, 2, 3, 0x3c]))
        transport.emit([1, 0]) // invalid protocol reply length
        await settle()
        XCTAssertEqual(controller.connectionState, .initializing)
        controller.disconnect()
    }

    func testQueuedEQCurvesAreReplacedAndCannotOverridePreset() async throws {
        let transport = TestTransport()
        let controller = await connected(transport, timing: .init(equalizerDelay: 5_000_000))
        transport.messages.removeAll()
        transport.acknowledgeWrites = false
        controller.setSpeakToChatEnabled(true) // occupy the one outstanding slot
        controller.setEqualizerBands(Array(repeating: 1, count: 10))
        try await Task.sleep(nanoseconds: 15_000_000)
        controller.setEqualizerBands(Array(repeating: 2, count: 10))
        try await Task.sleep(nanoseconds: 15_000_000)
        controller.setEqualizerPreset(.off)
        transport.acknowledgeWrites = true
        transport.emit([], type: .ack, sequence: transport.commands[0].sequenceNumber ^ 1)
        await settle()
        XCTAssertEqual(transport.commands.map(\.payload), [[0xf8, 0x0c, 0, 1], [0x58, 4, 0, 0]])
        controller.disconnect()
    }

    func testLogDefaultsAreNamespacedAndOffByDefault() {
        let controller = HeadphonesController(defaults: defaults)
        XCTAssertFalse(controller.protocolLoggingEnabled)
        XCTAssertTrue(controller.protocolLogURL?.path.contains("boring.notch/XM6/") == true)
        controller.protocolLoggingEnabled = true
        XCTAssertEqual(defaults.object(forKey: "xm6.protocolLoggingEnabled") as? Bool, true)
    }
}
