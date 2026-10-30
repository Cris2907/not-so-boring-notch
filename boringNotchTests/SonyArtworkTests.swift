import AppKit
import ImageIO
import SonyHeadphonesKit
import XCTest
@testable import boringNotch

private actor ArtworkDownloads {
    var count = 0
    func increment() { count += 1 }
}

final class SonyArtworkCatalogTests: XCTestCase {
    private let image = URL(string: "https://hpc-image.data-gateway.seeds.services/still.png")!
    func testExactColorDefaultFallbackAndMissingAnimation() {
        let black = SonyArtworkEntry(model: "WF-1000XM6", color: 1, imageURL: image, animationURL: image)
        let fallback = SonyArtworkEntry(model: "WF-1000XM6", color: 0, imageURL: image, animationURL: nil)
        let catalog = SonyArtworkCatalog(entries: [black, fallback])
        XCTAssertEqual(catalog.entry(model: "wf-1000xm6", color: 1), black)
        XCTAssertEqual(catalog.entry(model: "WF-1000XM6", color: 0xfe), fallback)
        XCTAssertEqual(catalog.entry(model: "WF-1000XM6", color: nil), fallback)
        XCTAssertNil(catalog.entry(model: "WH-1000XM6", color: 1))
    }
    func testBundledCatalogContainsHeadphoneArtworkAndNoKeys() throws {
        let catalog = SonyArtworkCatalog(bundle: Bundle(for: XM6Activity.self))
        XCTAssertGreaterThan(catalog.entries.count, 100)
        XCTAssertNotNil(catalog.entry(model: "WH-1000XM6", color: 1)?.animationURL)
        XCTAssertNil(catalog.entry(model: "WF-1000XM5", color: 1)?.animationURL)
        XCTAssertFalse(catalog.entries.contains { $0.model == "LinkBuds Speaker" })
    }
    func testFrameTimingUsesUnclampedDelayAndRejectsInvalidValues() {
        XCTAssertEqual(SonyFrameDecoder.duration([kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGUnclampedDelayTime: 0.04]]), 0.04)
        XCTAssertEqual(SonyFrameDecoder.duration([kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: -1.0]]), 1.0 / 30)
    }
}

@MainActor
final class SonyIdentityResolutionTests: XCTestCase {
    func testRenamedModelAssignmentPrecedenceAndDisconnect() throws {
        let suite = "SonyIdentityResolutionTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let assignments = HeadphoneModelAssignments(defaults: defaults)
        let store = SonyDeviceIdentityStore(assignments: assignments, loadArtwork: { _ in })
        let device = BluetoothAudioDevice(audioObjectID: 1, name: "Cristian’s headphones", manufacturer: nil,
            modelUID: nil, transportType: 0, bluetoothAddress: "AA-BB-CC-DD-EE-FF", isBluetooth: true, detectedAt: Date())
        store.record(.init(modelName: "WF-1000XM6", series: 0x32, color: 3), address: "aa:bb:cc:dd:ee:ff")
        XCTAssertEqual(store.profile(for: device).displayName, "Sony WF-1000XM6")
        XCTAssertEqual(store.artworkEntry(address: device.bluetoothAddress, profile: store.profile(for: device))?.color, 3)
        XCTAssertNil(store.identity(for: "AA-BB-CC-DD-EE-00"))
        assignments.assign("sony-wh-1000xm6", to: device.bluetoothAddress!)
        XCTAssertEqual(store.profile(for: device).displayName, "Sony WH-1000XM6")
        XCTAssertEqual(store.artworkEntry(address: device.bluetoothAddress, profile: store.profile(for: device))?.color, 0)
        assignments.assign(nil, to: device.bluetoothAddress!)
        XCTAssertEqual(store.profile(for: device).displayName, "Sony WF-1000XM6")
        store.disconnected(device.bluetoothAddress)
        XCTAssertNil(store.identity(for: device.bluetoothAddress))
    }
}

final class SonyArtworkCacheTests: XCTestCase {
    private func png() throws -> Data {
        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 32, bitsPerPixel: 32)!
        return try XCTUnwrap(image.representation(using: .png, properties: [:]))
    }
    func testDownloadDeduplicationOfflineReuseAndBoundedEviction() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = try png(), downloads = ArtworkDownloads()
        let cache = SonyArtworkCache(directory: directory, limit: bytes.count + 1) { request in
            await downloads.increment()
            try await Task.sleep(nanoseconds: 15_000_000)
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try bytes.write(to: temporary)
            return (temporary, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let url = URL(string: "https://hpc-image.data-gateway.seeds.services/first.png")!
        async let first = cache.file(for: url)
        async let second = cache.file(for: url)
        let results = try await [first, second]
        XCTAssertEqual(results[0], results[1])
        let count = await downloads.count
        XCTAssertEqual(count, 1)
        _ = try await cache.file(for: url)
        let offlineCount = await downloads.count
        XCTAssertEqual(offlineCount, 1)
        let next = try await cache.file(for: URL(string: "https://hpc-image.data-gateway.seeds.services/second.png")!)
        XCTAssertTrue(FileManager.default.fileExists(atPath: next.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: results[0].path))
    }
    func testFailedOrInvalidDownloadsAreNotCachedAndCanRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let downloads = ArtworkDownloads()
        let cache = SonyArtworkCache(directory: directory) { request in
            await downloads.increment()
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data("not a PNG".utf8).write(to: temporary)
            return (temporary, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let url = URL(string: "https://hpc-image.data-gateway.seeds.services/bad.png")!
        for _ in 0..<2 {
            do { _ = try await cache.file(for: url); XCTFail("Expected invalid image rejection") } catch { }
        }
        let count = await downloads.count
        XCTAssertEqual(count, 2)
        XCTAssertFalse(SonyArtworkCache.isAllowed(URL(string: "http://hpc-image.data-gateway.seeds.services/a.png")!))
        XCTAssertFalse(SonyArtworkCache.isAllowed(URL(string: "https://example.com/a.png")!))
    }
}

final class SonyAPNGDecoderTests: XCTestCase {
    func testBlankFramesDoNotReplaceVisibleProductAndFramesAreDownsampled() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 3, nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 1]] as CFDictionary)
        for visible in [false, true, false] {
            let context = try XCTUnwrap(CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8,
                bytesPerRow: 128 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            if visible { context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 128, height: 128)) }
            CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()),
                [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: 0.04]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let decoder = SonyFrameDecoder(url: url)
        let count = await decoder.count()
        XCTAssertEqual(count, 3)
        var lastVisible: CGImage?
        for index in 0..<count {
            let result = await decoder.frame(index, pixels: 42)
            let (frame, duration) = try XCTUnwrap(result)
            XCTAssertLessThanOrEqual(frame.width, 42)
            XCTAssertEqual(duration, 0.04, accuracy: 0.001)
            if SonyFrameDecoder.isVisible(frame) { lastVisible = frame }
        }
        XCTAssertNotNil(lastVisible)
    }
}

@MainActor
final class SonyNotificationTimingTests: XCTestCase {
    func testLateArtworkExtendsOnlyTheCurrentBluetoothNotification() {
        let coordinator = BoringViewCoordinator.shared
        let saved = coordinator.sneakPeek
        defer { coordinator.sneakPeek = saved }
        coordinator.sneakPeek = .init()
        XCTAssertFalse(coordinator.extendBluetoothSneakPeek(duration: 5.5))
        XCTAssertFalse(coordinator.sneakPeek.show)
        coordinator.sneakPeek = .init(show: true, type: .battery)
        XCTAssertFalse(coordinator.extendBluetoothSneakPeek(duration: 5.5))
        coordinator.sneakPeek = .init(show: true, type: .bluetooth)
        XCTAssertTrue(coordinator.extendBluetoothSneakPeek(duration: 5.5))
        XCTAssertTrue(coordinator.sneakPeek.show)
        coordinator.sneakPeek = .init(show: false, type: .bluetooth)
        XCTAssertFalse(coordinator.extendBluetoothSneakPeek(duration: 5.5))
        XCTAssertFalse(coordinator.sneakPeek.show)
    }
}
