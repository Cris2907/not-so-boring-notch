import Combine
import CoreAudio
import Foundation

struct BluetoothAudioDevice: Equatable, Identifiable {
    let audioObjectID: AudioObjectID
    let name: String
    let manufacturer: String?
    let modelUID: String?
    let transportType: UInt32
    let bluetoothAddress: String?
    let isBluetooth: Bool
    let detectedAt: Date

    var id: AudioObjectID { audioObjectID }

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Bluetooth headphones" : trimmedName
    }
}

struct BluetoothHeadphoneProfile: Equatable, Identifiable {
    let id: String
    let displayName: String
    let imageAssetName: String?
    let symbolName: String
    let modelKeys: [String]
    let manufacturerKeys: [String]
    let namePatterns: [String]
    let bluetoothAddressPrefixes: [String]

    init(
        id: String,
        displayName: String,
        imageAssetName: String? = nil,
        symbolName: String = "headphones",
        modelKeys: [String] = [],
        manufacturerKeys: [String] = [],
        namePatterns: [String] = [],
        bluetoothAddressPrefixes: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.imageAssetName = imageAssetName
        self.symbolName = symbolName
        self.modelKeys = modelKeys.map(BluetoothHeadphoneProfileStore.normalize)
        self.manufacturerKeys = manufacturerKeys.map(BluetoothHeadphoneProfileStore.normalize)
        self.namePatterns = namePatterns.map(BluetoothHeadphoneProfileStore.normalize)
        self.bluetoothAddressPrefixes = bluetoothAddressPrefixes.map(BluetoothHeadphoneProfileStore.normalize)
    }

    func resolvedDisplayName(for device: BluetoothAudioDevice) -> String {
        device.displayName == "Bluetooth headphones" ? displayName : device.displayName
    }
}

enum BluetoothHeadphoneProfileStore {
    static let fallbackProfile = BluetoothHeadphoneProfile(
        id: "generic-bluetooth-headphones",
        displayName: "Bluetooth headphones",
        symbolName: "headphones"
    )

    static let sonyModelNames = [
        "WH-1000XM2", "WH-1000XM3", "WH-1000XM4", "WH-1000XM5", "WH-1000XM6",
        "WH-CH520", "WH-CH720N", "WH-XB900N", "WH-XB910N", "MDR-XB950BT",
        "WF-1000XM4", "WF-1000XM5", "WF-C700N", "LinkBuds S"
    ]

    static let sonyProfiles: [BluetoothHeadphoneProfile] = sonyModelNames.map { model in
        let key = model.lowercased().replacingOccurrences(of: " ", with: "-")
        return BluetoothHeadphoneProfile(
            id: "sony-" + key, displayName: "Sony " + model,
            imageAssetName: "headphones-sony-" + key,
            modelKeys: [model], manufacturerKeys: ["sony"], namePatterns: [model]
        )
    }

    static let profiles: [BluetoothHeadphoneProfile] = sonyProfiles + [
        BluetoothHeadphoneProfile(
            id: "airpods-pro",
            displayName: "AirPods Pro",
            imageAssetName: "headphones-airpods-pro",
            symbolName: "airpodspro",
            modelKeys: ["airpodspro", "airpods pro", "appleairpodspro", "apple airpods pro"],
            manufacturerKeys: ["apple"],
            namePatterns: ["airpods pro", "airpodspro"]
        ),
        BluetoothHeadphoneProfile(
            id: "airpods-max",
            displayName: "AirPods Max",
            imageAssetName: "headphones-airpods-max",
            symbolName: "airpodsmax",
            modelKeys: ["airpodsmax", "airpods max", "appleairpodsmax", "apple airpods max"],
            manufacturerKeys: ["apple"],
            namePatterns: ["airpods max", "airpodsmax"]
        ),
        BluetoothHeadphoneProfile(
            id: "airpods",
            displayName: "AirPods",
            imageAssetName: "headphones-airpods",
            symbolName: "airpods",
            modelKeys: ["airpods", "appleairpods", "apple airpods"],
            manufacturerKeys: ["apple"],
            namePatterns: ["airpods"]
        ),
        BluetoothHeadphoneProfile(
            id: "beats",
            displayName: "Beats",
            imageAssetName: "headphones-beats",
            symbolName: "beats.headphones",
            manufacturerKeys: ["apple", "beats"],
            namePatterns: ["beats", "powerbeats", "studio buds", "studio pro", "fit pro"]
        ),
        BluetoothHeadphoneProfile(
            id: "sony-wh",
            displayName: "Sony headphones",
            imageAssetName: "headphones-sony-wh",
            symbolName: "headphones",
            manufacturerKeys: ["sony"],
            namePatterns: ["wh-1000", "wh1000", "wf-1000", "wf1000", "linkbuds"]
        ),
        BluetoothHeadphoneProfile(
            id: "bose-quietcomfort",
            displayName: "Bose headphones",
            imageAssetName: "headphones-bose-qc",
            symbolName: "headphones",
            manufacturerKeys: ["bose"],
            namePatterns: ["quietcomfort", "qc", "bose"]
        )
    ]

    static func profile(for device: BluetoothAudioDevice, assignments: [String: String] = [:]) -> BluetoothHeadphoneProfile {
        guard device.isBluetooth else { return fallbackProfile }

        if let address = BluetoothAddress.canonical(device.bluetoothAddress),
           let id = assignments[address], let assigned = profiles.first(where: { $0.id == id }) {
            return assigned
        }

        if let model = sonyProfiles.first(where: { matchesSonyModel($0, in: device.modelUID) }) {
            return model
        }
        // Model metadata wins over a potentially renamed Bluetooth display name.
        let normalizedModel = normalize(device.modelUID)
        let normalizedManufacturer = normalize(device.manufacturer)
        let normalizedName = normalize(device.name)
        let normalizedAddress = normalize(device.bluetoothAddress)

        if let exactMatch = profiles.dropFirst(sonyProfiles.count).first(where: { profile in
            matchesAny(profile.modelKeys, in: normalizedModel)
                || profile.bluetoothAddressPrefixes.contains(where: normalizedAddress.hasPrefix)
        }) {
            return exactMatch
        }

        if let model = sonyProfiles.first(where: { matchesSonyModel($0, in: device.name) }) {
            return model
        }

        if let manufacturerMatch = profiles.dropFirst(sonyProfiles.count).first(where: { profile in
            matchesAny(profile.manufacturerKeys, in: normalizedManufacturer)
                && matchesAny(profile.namePatterns, in: normalizedName)
        }) {
            return manufacturerMatch
        }

        if let nameMatch = profiles.dropFirst(sonyProfiles.count).first(where: { profile in
            matchesAny(profile.namePatterns, in: normalizedName)
        }) {
            return nameMatch
        }

        return fallbackProfile
    }

    private static func matchesSonyModel(_ profile: BluetoothHeadphoneProfile, in value: String?) -> Bool {
        let candidate = normalize(value)
        return profile.modelKeys.contains { key in
            let parts = key.split(whereSeparator: { $0 == "-" || $0.isWhitespace })
            let model = parts.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "[\\s_\\-]*")
            let pattern = "(?<![a-z0-9])" + model + "(?![a-z0-9])"
            return candidate.range(of: pattern, options: .regularExpression) != nil
        }
    }

    static func normalize(_ value: String?) -> String {
        value?
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func matchesAny(_ patterns: [String], in candidate: String) -> Bool {
        guard !candidate.isEmpty else { return false }
        return patterns.contains { pattern in
            !pattern.isEmpty && candidate.contains(pattern)
        }
    }
}

/// Canonical keys are twelve lowercase hexadecimal digits; display formatting
/// and CoreAudio suffixes never become part of a saved device identity.
enum BluetoothAddress {
    static func canonical(_ value: String?) -> String? {
        guard let value else { return nil }
        let compact = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").lowercased()
        guard compact.range(of: "^[0-9a-f]{12}$", options: .regularExpression) != nil else { return nil }
        return compact
    }

    static func fromDeviceUID(_ uid: String?) -> String? {
        guard let uid else { return nil }
        let pattern = "(?i)(?<![a-z0-9])(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}(?![a-z0-9])|(?<![a-z0-9])[0-9a-f]{12}(?![a-z0-9])"
        guard let range = uid.range(of: pattern, options: .regularExpression) else { return nil }
        return canonical(String(uid[range]))
    }
}

struct PairedHeadphoneIdentity: Identifiable, Equatable {
    let address: String
    let name: String
    let isConnected: Bool
    var id: String { address }
}

enum BluetoothHeadphoneAssociation {
    static func match(address: String?, name: String, devices: [PairedHeadphoneIdentity]) -> PairedHeadphoneIdentity? {
        if let address = BluetoothAddress.canonical(address) {
            // A known audio address must never inherit an override from a different device.
            let matches = devices.filter { BluetoothAddress.canonical($0.address) == address }
            return matches.count == 1 ? matches[0] : nil
        }
        let name = BluetoothHeadphoneProfileStore.normalize(name)
        guard !name.isEmpty else { return nil }
        let matches = devices.filter {
            $0.isConnected && BluetoothHeadphoneProfileStore.normalize($0.name) == name
        }
        return matches.count == 1 ? matches[0] : nil
    }
}

final class HeadphoneModelAssignments: ObservableObject {
    static let shared = HeadphoneModelAssignments()
    private static let storageKey = "bluetoothHeadphoneModelAssignments"
    @Published private(set) var assignments: [String: String]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var loaded: [String: String] = [:]
        for (address, id) in defaults.dictionary(forKey: Self.storageKey) ?? [:] {
            if let address = BluetoothAddress.canonical(address), let id = id as? String {
                loaded[address] = id
            }
        }
        assignments = loaded
    }

    func assignedProfileID(for address: String?) -> String? {
        guard let address = BluetoothAddress.canonical(address), let id = assignments[address],
              BluetoothHeadphoneProfileStore.profiles.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    func assign(_ profileID: String?, to address: String) {
        guard let address = BluetoothAddress.canonical(address) else { return }
        if let profileID, !BluetoothHeadphoneProfileStore.profiles.contains(where: { $0.id == profileID }) { return }
        var updated = assignments
        updated[address] = profileID
        guard updated != assignments else { return }
        assignments = updated
        defaults.set(updated, forKey: Self.storageKey)
    }

    func profile(for device: BluetoothAudioDevice) -> BluetoothHeadphoneProfile {
        BluetoothHeadphoneProfileStore.profile(for: device, assignments: assignments)
    }

    func profile(name: String, address: String?) -> BluetoothHeadphoneProfile {
        profile(for: BluetoothAudioDevice(audioObjectID: 0, name: name, manufacturer: nil,
            modelUID: nil, transportType: 0, bluetoothAddress: address, isBluetooth: true, detectedAt: .distantPast))
    }
}
