import AppKit
import ImageIO
import SonyHeadphonesKit
import SwiftUI

/// One source and one decoded frame at a time. ImageIO composites APNG delta frames.
actor SonyFrameDecoder {
    private var source: CGImageSource?
    private let url: URL
    init(url: URL) { self.url = url }
    private func open() -> CGImageSource? {
        if source == nil { source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) }
        return source
    }
    func count() -> Int { open().map(CGImageSourceGetCount) ?? 0 }
    static func duration(_ properties: [CFString: Any]) -> Double {
        let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any] ?? [:]
        let delay = (png[kCGImagePropertyAPNGUnclampedDelayTime] as? Double)
            ?? (png[kCGImagePropertyAPNGDelayTime] as? Double) ?? (1.0 / 30)
        return delay.isFinite && delay > 0 ? max(0.01, delay) : 1.0 / 30
    }
    func frame(_ index: Int, pixels: Int) -> (CGImage, Double)? {
        guard let source = open(), index < CGImageSourceGetCount(source),
              let image = CGImageSourceCreateThumbnailAtIndex(source, index, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldCacheImmediately: false
              ] as CFDictionary) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        return (image, Self.duration(properties))
    }
    nonisolated static func isVisible(_ image: CGImage) -> Bool {
        var bytes = [UInt8](repeating: 0, count: 8 * 8 * 4)
        return bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 8, height: 8, bitsPerComponent: 8,
                bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 8))
            return stride(from: 3, to: buffer.count, by: 4).contains { buffer[$0] > 8 }
        }
    }
}

struct SonyDeviceArtwork: View {
    let address: String?
    let profile: BluetoothHeadphoneProfile
    let isConnected: Bool
    var size: CGFloat = 112
    @ObservedObject private var identities = SonyDeviceIdentityStore.shared
    @ObservedObject private var artwork = SonyArtworkStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var frame: NSImage?
    @MainActor
    init(address: String?, profile: BluetoothHeadphoneProfile, isConnected: Bool, size: CGFloat = 112,
         identities: SonyDeviceIdentityStore? = nil, artwork: SonyArtworkStore? = nil) {
        self.address = address; self.profile = profile; self.isConnected = isConnected; self.size = size
        _identities = ObservedObject(wrappedValue: identities ?? .shared)
        _artwork = ObservedObject(wrappedValue: artwork ?? .shared)
    }

    private var entry: SonyArtworkEntry? {
        identities.artworkEntry(address: address, profile: profile)
    }
    private var staticFile: URL? { artwork.localFile(for: entry?.imageURL) }
    private var animationFile: URL? { artwork.localFile(for: entry?.animationURL) }
    private struct Playback: Hashable {
        let address: String?
        let profile: String
        let animation: URL?
        let still: URL?
        let reduced: Bool
        let connected: Bool
    }
    var body: some View {
        Group {
            if isConnected, let frame {
                Image(nsImage: frame).resizable().scaledToFit()
            } else if isConnected, let name = profile.imageAssetName, let image = NSImage(named: name) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: profile.symbolName).resizable().scaledToFit().padding(size * 0.22)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: Playback(address: address, profile: profile.id, animation: reduceMotion ? nil : animationFile,
                           still: reduceMotion || animationFile == nil ? staticFile : nil, reduced: reduceMotion, connected: isConnected)) {
            frame = nil
            guard isConnected else { return }
            if let entry { artwork.load(entry) }
            let pixels = Int(ceil(size * displayScale))
            if let file = staticFile, let (image, _) = await SonyFrameDecoder(url: file).frame(0, pixels: pixels), !Task.isCancelled {
                frame = NSImage(cgImage: image, size: .zero)
            }
            guard !reduceMotion, let file = animationFile else { return }
            let decoder = SonyFrameDecoder(url: file)
            let count = await decoder.count()
            var nextFrameTime = Date.timeIntervalSinceReferenceDate
            for index in 0..<count {
                guard !Task.isCancelled, let (image, duration) = await decoder.frame(index, pixels: pixels) else { return }
                guard !Task.isCancelled else { return }
                if SonyFrameDecoder.isVisible(image) { frame = NSImage(cgImage: image, size: .zero) }
                nextFrameTime += duration
                let delay = max(0, nextFrameTime - Date.timeIntervalSinceReferenceDate)
                do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
            }
            // The last visible frame stays on screen; blank trailing frames cannot erase it.
        }
    }
}
