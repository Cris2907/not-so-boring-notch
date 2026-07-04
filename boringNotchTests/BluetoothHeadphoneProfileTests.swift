import CoreAudio
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