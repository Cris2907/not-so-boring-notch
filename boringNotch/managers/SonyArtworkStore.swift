import AppKit
import Combine
import CryptoKit
import ImageIO
import SonyHeadphonesKit

struct SonyArtworkEntry: Codable, Equatable, Sendable {
    let model: String
    let color: Int
    let imageURL: URL
    let animationURL: URL?
}

struct SonyArtworkCatalog {
    let entries: [SonyArtworkEntry]
    init(entries: [SonyArtworkEntry]) { self.entries = entries }
    init(bundle: Bundle = .main) {
        let url = bundle.url(forResource: "catalog", withExtension: "json", subdirectory: "SonyArtwork")
        entries = url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([SonyArtworkEntry].self, from: $0) } ?? []
    }
    func entry(model: String, color: UInt8?) -> SonyArtworkEntry? {
        let models = entries.filter { $0.model.caseInsensitiveCompare(model) == .orderedSame }
        if let color, let exact = models.first(where: { $0.color == Int(color) }) { return exact }
        return models.first { $0.color == 0 }
    }
}

/// URL-addressed files; no client key or account credentials are needed for artwork.
actor SonyArtworkCache {
    static let shared = SonyArtworkCache()
    private let directory: URL
    private let download: @Sendable (URLRequest) async throws -> (URL, URLResponse)
    private let limit: Int
    private var pending: [URL: Task<URL, Error>] = [:]
    init(directory: URL? = nil, limit: Int = 100 * 1024 * 1024,
         download: @escaping @Sendable (URLRequest) async throws -> (URL, URLResponse) = { try await URLSession.shared.download(for: $0) }) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("boring.notch/SonyArtwork", isDirectory: true)
        self.download = download
        self.limit = limit
    }
    nonisolated static func isAllowed(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "hpc-image.data-gateway.seeds.services" && url.user == nil && url.password == nil
    }
    nonisolated static func isValid(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let type = CGImageSourceGetType(source), type as String == "public.png",
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 4096, height <= 4096,
              CGImageSourceGetCount(source) <= 600 else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }
    func file(for url: URL) async throws -> URL {
        guard Self.isAllowed(url) else { throw URLError(.unsupportedURL) }
        if let task = pending[url] { return try await task.value }
        let directory = directory, download = download
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined() + ".png"
        let destination = directory.appendingPathComponent(name)
        let task = Task<URL, Error> {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path), Self.isValid(destination) {
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
                return destination
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 25
            let (temporary, response) = try await download(request)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let finalURL = response.url, Self.isAllowed(finalURL),
                  let bytes = try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  bytes > 0, bytes <= 25 * 1024 * 1024, Self.isValid(temporary) else { throw URLError(.cannotDecodeContentData) }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
            return destination
        }
        pending[url] = task
        do {
            let result = try await task.value
            pending[url] = nil
            trim(excluding: result)
            return result
        } catch { pending[url] = nil; throw error }
    }
    private func trim(excluding retained: URL) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? []
        let records = files.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var size = records.reduce(0) { $0 + $1.1 }
        for (url, bytes, _) in records where size > limit && url != retained {
            if (try? FileManager.default.removeItem(at: url)) != nil { size -= bytes }
        }
    }
}

@MainActor
final class SonyArtworkStore: ObservableObject {
    static let shared = SonyArtworkStore()
    let catalog = SonyArtworkCatalog()
    @Published private(set) var files: [URL: URL] = [:]
    private var loading: Set<URL> = []
    init(files: [URL: URL] = [:]) { self.files = files }
    func localFile(for url: URL?) -> URL? {
        guard let url, let file = files[url], FileManager.default.fileExists(atPath: file.path) else { return nil }
        return file
    }
    func load(_ entry: SonyArtworkEntry) {
        for url in [entry.imageURL, entry.animationURL].compactMap({ $0 }) where localFile(for: url) == nil && !loading.contains(url) {
            loading.insert(url)
            Task { [weak self] in
                let file = try? await SonyArtworkCache.shared.file(for: url)
                guard let self else { return }
                self.loading.remove(url)
                if let file { self.files[url] = file }
            }
        }
    }
}
