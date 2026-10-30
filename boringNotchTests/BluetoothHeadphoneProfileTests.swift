import AppKit
import Combine
import CoreAudio
import SwiftUI
import XCTest
@testable import boringNotch

final class BluetoothHeadphoneProfileStoreTests: XCTestCase {
    func testExactModelKeyBeatsGenericNamePattern() {
        let device = makeDevice(
            name: "Cristian's AirPods",
            manufacturer: "Apple Inc.",
            modelUID: "AppleAirPodsMax"
        )

        XCTAssertEqual(BluetoothHeadphoneProfileStore.profile(for: device).id, "airpods-max")
    }

    func testRenamedAirPodsProMatchesNamePattern() {
        let device = makeDevice(
            name: "Cristian's AirPods Pro",
            manufacturer: nil,
            modelUID: nil
        )

        XCTAssertEqual(BluetoothHeadphoneProfileStore.profile(for: device).id, "airpods-pro")
    }

    func testUnknownBluetoothDeviceUsesGenericFallback() {
        let device = makeDevice(name: "Kitchen headphones")

        XCTAssertEqual(BluetoothHeadphoneProfileStore.profile(for: device), BluetoothHeadphoneProfileStore.fallbackProfile)
    }

    func testNonBluetoothDeviceDoesNotMatchHeadphoneName() {
        let device = makeDevice(name: "AirPods Pro", isBluetooth: false)

        XCTAssertEqual(BluetoothHeadphoneProfileStore.profile(for: device), BluetoothHeadphoneProfileStore.fallbackProfile)
    }

    func testEverySonyModelAndNormalizedNameSelectsItsOwnArtwork() throws {
        XCTAssertEqual(BluetoothHeadphoneProfileStore.sonyProfiles.count, 14)
        for model in BluetoothHeadphoneProfileStore.sonyModelNames {
            for name in [model, "Cristian’s " + model + " headphones", model.lowercased().replacingOccurrences(of: "-", with: ""),
                         model.replacingOccurrences(of: "-", with: " ")] {
                let profile = BluetoothHeadphoneProfileStore.profile(for: makeDevice(name: name))
                XCTAssertEqual(profile.displayName, "Sony " + model, name)
                let image = try XCTUnwrap(NSImage(named: try XCTUnwrap(profile.imageAssetName)))
                XCTAssertGreaterThan(image.size.width, 0)
                XCTAssertGreaterThan(image.size.height, 0)
            }
        }
    }

    func testMetadataWinsOverRenamedModelAndPartialModelDoesNotMatch() {
        XCTAssertEqual(BluetoothHeadphoneProfileStore.profile(for: makeDevice(
            name: "WH-1000XM5", modelUID: "WH-1000XM6")).id, "sony-wh-1000xm6")
        XCTAssertEqual(BluetoothHeadphoneProfileStore.profile(for: makeDevice(
            name: "WH-1000XM6", modelUID: "AppleAirPodsMax")).id, "airpods-max")
        XCTAssertEqual(BluetoothHeadphoneProfileStore.profile(for: makeDevice(name: "WH-1000XM60")).id, "sony-wh")
        XCTAssertEqual(BluetoothHeadphoneProfileStore.profile(for: makeDevice(name: "LinkBuds")).id, "sony-wh")
        XCTAssertEqual(BluetoothHeadphoneProfileStore.profile(for: makeDevice(name: "Beats Studio Pro")).id, "beats")
        XCTAssertEqual(BluetoothHeadphoneProfileStore.profile(for: makeDevice(name: "Bose QuietComfort")).id, "bose-quietcomfort")
    }

    func testAddressNormalizationAndAudioUIDExtraction() {
        for address in ["AA-BB-CC-DD-EE-FF", "aa:bb:cc:dd:ee:ff", " AABBCCDDEEFF "] {
            XCTAssertEqual(BluetoothAddress.canonical(address), "aabbccddeeff")
        }
        XCTAssertEqual(BluetoothAddress.fromDeviceUID("AA-BB-CC-DD-EE-FF:output"), "aabbccddeeff")
        XCTAssertEqual(BluetoothAddress.fromDeviceUID("Bluetooth:AA:BB:CC:DD:EE:FF:input"), "aabbccddeeff")
        XCTAssertEqual(BluetoothAddress.fromDeviceUID("Bluetooth_aabbccddeeff-output"), "aabbccddeeff")
        for invalid in ["headphones", "AA:BB:CC", "aabbccddeeff00", "zz:bb:cc:dd:ee:ff"] {
            XCTAssertNil(BluetoothAddress.canonical(invalid))
            XCTAssertNil(BluetoothAddress.fromDeviceUID(invalid))
        }
    }

    func testAssignmentsPersistAcrossRenameAndAutomaticRestoresDetection() throws {
        let suite = "HeadphoneAssignmentsTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HeadphoneModelAssignments(defaults: defaults)
        var updates: [[String: String]] = []
        let observation = store.$assignments.sink { updates.append($0) }
        defer { observation.cancel() }
        store.assign("sony-wh-1000xm6", to: "AA-BB-CC-DD-EE-FF")
        XCTAssertEqual(updates.last?["aabbccddeeff"], "sony-wh-1000xm6")
        let reloaded = HeadphoneModelAssignments(defaults: defaults)
        XCTAssertEqual(reloaded.profile(name: "Renamed again", address: "aa:bb:cc:dd:ee:ff").id, "sony-wh-1000xm6")
        let conflicting = makeDevice(name: "AirPods Pro", modelUID: "AppleAirPodsMax", bluetoothAddress: "AABBCCDDEEFF")
        XCTAssertEqual(reloaded.profile(for: conflicting).id, "sony-wh-1000xm6")
        XCTAssertEqual(reloaded.profile(name: "Other device", address: "11:22:33:44:55:66").id, "generic-bluetooth-headphones")
        reloaded.assign(nil, to: "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(HeadphoneModelAssignments(defaults: defaults).profile(for: conflicting).id, "airpods-max")
        reloaded.assign("not-a-real-model", to: "AA:BB:CC:DD:EE:FF")
        reloaded.assign("sony-wh-1000xm6", to: "invalid")
        XCTAssertTrue(reloaded.assignments.isEmpty)
    }

    func testUnknownStoredModelAndMissingAddressFallBackWithoutMisidentification() throws {
        let suite = "HeadphoneAssignmentsTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["AA-BB-CC-DD-EE-FF": "removed-profile"], forKey: "bluetoothHeadphoneModelAssignments")
        let store = HeadphoneModelAssignments(defaults: defaults)
        XCTAssertNil(store.assignedProfileID(for: "aa:bb:cc:dd:ee:ff"))
        XCTAssertEqual(store.profile(name: "WH-1000XM6", address: "aabbccddeeff").id, "sony-wh-1000xm6")
        XCTAssertEqual(store.profile(name: "Renamed", address: nil).id, "generic-bluetooth-headphones")
        XCTAssertEqual(store.profile(for: makeDevice(name: "WH-1000XM6", isBluetooth: false)).id, "generic-bluetooth-headphones")
    }

    func testAddressAssociationWinsAndAmbiguousNamesRemainUnassigned() {
        let first = PairedHeadphoneIdentity(address: "aabbccddeeff", name: "My headphones", isConnected: true)
        let second = PairedHeadphoneIdentity(address: "112233445566", name: "My headphones", isConnected: true)
        XCTAssertEqual(BluetoothHeadphoneAssociation.match(address: "AA:BB:CC:DD:EE:FF", name: "Renamed", devices: [first, second]), first)
        XCTAssertNil(BluetoothHeadphoneAssociation.match(address: nil, name: "My headphones", devices: [first, second]))
        XCTAssertNil(BluetoothHeadphoneAssociation.match(address: "001122334455", name: "My headphones", devices: [first]))
        XCTAssertEqual(BluetoothHeadphoneAssociation.match(address: nil, name: "my HEADPHONES", devices: [first]), first)
        XCTAssertNil(BluetoothHeadphoneAssociation.match(address: nil, name: "My", devices: [first]))
        let disconnected = PairedHeadphoneIdentity(address: first.address, name: first.name, isConnected: false)
        XCTAssertNil(BluetoothHeadphoneAssociation.match(address: nil, name: first.name, devices: [disconnected]))
    }

    @MainActor
    func testRenderedSonyNotificationsUseBundledArtwork() throws {
        for model in ["WH-1000XM6", "WF-1000XM5", "LinkBuds S"] {
            let device = makeDevice(name: model)
            let profile = BluetoothHeadphoneProfileStore.profile(for: device)
            XCTAssertNotNil(profile.imageAssetName.flatMap { NSImage(named: $0) })
            let hosting = NSHostingView(rootView: BluetoothDeviceActivity(
                device: device, profile: profile, closedNotchWidth: 200, height: 32
            ).frame(width: 592, height: 32).background(.black).environment(\.colorScheme, .dark))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 592, height: 32),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            defer { window.close() }
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let image = NSImage(size: hosting.bounds.size)
            image.addRepresentation(bitmap)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Bluetooth notification " + model
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func makeDevice(
        name: String,
        manufacturer: String? = nil,
        modelUID: String? = nil,
        bluetoothAddress: String? = nil,
        isBluetooth: Bool = true
    ) -> BluetoothAudioDevice {
        BluetoothAudioDevice(
            audioObjectID: AudioObjectID(42),
            name: name,
            manufacturer: manufacturer,
            modelUID: modelUID,
            transportType: 0,
            bluetoothAddress: bluetoothAddress,
            isBluetooth: isBluetooth,
            detectedAt: Date(timeIntervalSince1970: 0)
        )
    }
}