import Foundation

public struct SonyDeviceIdentity: Equatable, Sendable {
    public var modelName: String?
    public var series: UInt8?
    public var color: UInt8?

    public init(modelName: String? = nil, series: UInt8? = nil, color: UInt8? = nil) {
        self.modelName = modelName
        self.series = series
        self.color = color
    }

    public var supportsXM6Controls: Bool { modelName?.uppercased() == "WH-1000XM6" }
    public var isComplete: Bool { modelName != nil && series != nil && color != nil }
}

public enum SonySessionPurpose: Sendable { case controls, identityOnly }

public enum SonyIdentityReply: Equatable, Sendable {
    case modelName(String)
    case seriesAndColor(UInt8, UInt8)
}

public enum SonyIdentityProtocol {
    public static let modelRequest: [UInt8] = [0x04, 0x01]
    public static let colorRequest: [UInt8] = [0x04, 0x03]

    public static func decode(_ payload: [UInt8]) -> SonyIdentityReply? {
        guard payload.count >= 2, payload[0] == 0x05 else { return nil }
        switch payload[1] {
        case 1:
            guard payload.count >= 4, Int(payload[2]) == payload.count - 3,
                  let value = String(bytes: payload.dropFirst(3), encoding: .utf8),
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
            return .modelName(value)
        case 3:
            guard payload.count == 4 else { return nil }
            return .seriesAndColor(payload[2], payload[3])
        default: return nil
        }
    }
}
