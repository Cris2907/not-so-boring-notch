//
//  MediaControllerProtocol.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation
import AppKit
import Combine

protocol MediaControllerProtocol: ObservableObject {
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { get }
    var supportsVolumeControl: Bool { get }
    var supportsFavorite: Bool { get }
    
    func setFavorite(_ favorite: Bool) async
    func play() async
    func pause() async
    func seek(to time: Double) async
    func nextTrack() async
    func previousTrack() async
    func togglePlay() async
    func toggleShuffle() async
    func toggleRepeat() async
    func currentVolume() async -> Double?
    func setVolume(_ level: Double) async
    func isActive() -> Bool
    func updatePlaybackInfo() async
}


extension MediaControllerProtocol {
    func currentVolume() async -> Double? { nil }
}

/// App-local volume only: never changes the hardware output shared by chimes.
enum MediaPlayerVolume {
    static func read(bundleID: String) async -> Double? {
        guard let app = applicationName(bundleID),
              NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty == false,
              let value = try? await AppleScriptHelper.execute("tell application \"" + app + "\" to get sound volume") else { return nil }
        let volume = Double(value.int32Value) / 100
        return (0...1).contains(volume) ? volume : nil
    }

    static func write(_ volume: Double, bundleID: String) async {
        guard let app = applicationName(bundleID),
              !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return }
        try? await AppleScriptHelper.executeVoid("tell application \"" + app + "\" to set sound volume to " + String(Int(max(0, min(1, volume)) * 100)))
    }

    private static func applicationName(_ bundleID: String) -> String? {
        switch bundleID {
        case "com.apple.Music": "Music"
        case "com.spotify.client": "Spotify"
        default: nil
        }
    }
}
