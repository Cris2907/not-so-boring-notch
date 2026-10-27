import Foundation

/// A fresh transport is created for each attempt. Old delegates can never mutate a
/// replacement session, even when IOBluetooth reuses the same paired-device object.
public protocol HeadphonesTransport: AnyObject {
    var onEvent: ((RFCOMMConnectionEvent) -> Void)? { get set }
    func connect(toDeviceAddress address: String)
    func disconnect()
    func write(_ bytes: [UInt8])
}

/// Injectable deadlines keep hardware-free tests fast and deterministic.
public struct HeadphonesSessionTiming {
    public var connectTimeout: UInt64
    public var handshakeTimeout: UInt64
    public var stateTimeout: UInt64
    public var ackTimeout: UInt64
    public var equalizerDelay: UInt64

    public init(
        connectTimeout: UInt64 = 8_000_000_000,
        handshakeTimeout: UInt64 = 1_250_000_000,
        stateTimeout: UInt64 = 6_000_000_000,
        ackTimeout: UInt64 = 3_000_000_000,
        equalizerDelay: UInt64 = 120_000_000
    ) {
        self.connectTimeout = connectTimeout
        self.handshakeTimeout = handshakeTimeout
        self.stateTimeout = stateTimeout
        self.ackTimeout = ackTimeout
        self.equalizerDelay = equalizerDelay
    }
}
