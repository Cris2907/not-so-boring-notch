import XCTest
@testable import SonyHeadphonesKit

final class SonyIdentityProtocolTests: XCTestCase {
    func testRepliesPreserveUnknownColorsAndRejectMalformedOrUnrelatedPayloads() {
        XCTAssertEqual(SonyIdentityProtocol.decode([5, 1, 10] + Array("WF-1000XM6".utf8)), .modelName("WF-1000XM6"))
        XCTAssertEqual(SonyIdentityProtocol.decode([5, 3, 0x32, 0xfe]), .seriesAndColor(0x32, 0xfe))
        for bad: [UInt8] in [[], [5], [5, 1, 10, 65], [5, 1, 1, 0], [5, 1, 1, 0xff], [5, 1, 0], [5, 3, 0], [5, 3, 0, 0, 0], [5, 2, 1, 65], [6, 3, 0, 0]] {
            XCTAssertNil(SonyIdentityProtocol.decode(bad), "\(bad)")
        }
    }
}

@MainActor
final class SonyIdentitySessionTests: XCTestCase {
    private func settle() async { for _ in 0..<60 { await Task.yield() } }
    private func open(_ transport: TestTransport) async {
        transport.onEvent?(.opened); await settle()
        transport.emit([1, 0, 0, 0, 0, 0, 0, 0]); await settle()
    }
    func testIdentityOnlyDoesNotReadControlStateOrWriteSettings() async {
        let transport = TestTransport()
        let controller = HeadphonesController(purpose: .identityOnly, connectionFactory: { transport })
        controller.connect(toAddress: "AA-BB-CC-DD-EE-01", name: "Renamed")
        await open(transport)
        XCTAssertEqual(transport.commands.map(\.payload), [[0, 0], [4, 1], [4, 3]])
        transport.emit([5, 3, 0x32, 0xfe]); transport.emit([5, 1, 10] + Array("WF-1000XM6".utf8)); await settle()
        XCTAssertEqual(controller.identity, SonyDeviceIdentity(modelName: "WF-1000XM6", series: 0x32, color: 0xfe))
        XCTAssertFalse(controller.canControlXM6)
        controller.setSpeakToChatEnabled(true); controller.setAmbientSound(.init()); controller.refreshState()
        controller.sendRaw([0x68, 0x15, 1])
        await settle()
        XCTAssertEqual(transport.commands.count, 3)
        controller.disconnect()
        XCTAssertEqual(controller.identity, SonyDeviceIdentity())
    }
    func testControlsPreemptProbeAndLateProbeRepliesCannotPublishIdentity() async {
        let probeTransport = TestTransport(), fullTransport = TestTransport(), rejectedTransport = TestTransport()
        let probe = HeadphonesController(purpose: .identityOnly, connectionFactory: { probeTransport })
        let controls = HeadphonesController(connectionFactory: { fullTransport })
        let rejected = HeadphonesController(purpose: .identityOnly, connectionFactory: { rejectedTransport })
        probe.connect(toAddress: "AA-BB-CC-DD-EE-02", name: "Renamed"); await open(probeTransport)
        let stale = probeTransport.onEvent
        controls.connect(toAddress: "aa:bb:cc:dd:ee:02", name: "Renamed")
        XCTAssertTrue(probeTransport.disconnected)
        rejected.connect(toAddress: "AABBCCDDEE02", name: "Renamed")
        XCTAssertTrue(rejectedTransport.addresses.isEmpty)
        stale?(.dataReceived(SonyMessage(type: .command1, sequenceNumber: 0, payload: [5, 3, 1, 2]).encode()))
        await open(fullTransport)
        fullTransport.emit([5, 1, 10] + Array("WH-1000XM6".utf8)); await settle()
        XCTAssertTrue(controls.canControlXM6)
        XCTAssertEqual(probe.identity, SonyDeviceIdentity())
        controls.disconnect(); rejected.disconnect()
    }
    func testUnsupportedModelAndUnansweredIdentityNeverEnableControls() async {
        let transport = TestTransport()
        let controller = HeadphonesController(connectionFactory: { transport })
        controller.connect(toAddress: "AA-BB-CC-DD-EE-03", name: "WH-1000XM6")
        await open(transport)
        XCTAssertFalse(controller.canControlXM6)
        transport.emit([5, 1, 10] + Array("WF-1000XM5".utf8)); await settle()
        controller.setSpeakToChatEnabled(true); await settle()
        XCTAssertFalse(controller.canControlXM6)
        XCTAssertEqual(transport.commands.map(\.payload), [[0, 0], [4, 1], [4, 3]])
        controller.disconnect()
    }
}
