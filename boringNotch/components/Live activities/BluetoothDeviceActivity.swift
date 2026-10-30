import AppKit
import SwiftUI

struct BluetoothDeviceActivity: View {
    let device: BluetoothAudioDevice?
    let profile: BluetoothHeadphoneProfile
    let closedNotchWidth: CGFloat
    let height: CGFloat

    private var iconSize: CGFloat {
        if profile.id.hasPrefix("sony-") || profile.imageAssetName.flatMap({ NSImage(named: $0) }) != nil {
            return max(18, min(42, height - 2))
        }
        return max(18, min(34, height - 10))
    }

    private var deviceName: String {
        guard let device else { return profile.displayName }
        return profile.resolvedDisplayName(for: device)
    }

    var body: some View {
        NotchSafeZoneLayout(centerWidth: closedNotchWidth) {
            HStack(spacing: 8) {
                deviceIcon
                    .frame(width: iconSize, height: iconSize)
                MarqueeText(
                    .constant(deviceName),
                    textColor: .white,
                    minDuration: 1,
                    frameWidth: 128
                )
                .font(.caption)
                .fontWeight(.medium)
            }
            .frame(width: bluetoothNotificationSideWidth - 8, alignment: .leading)
            .padding(.leading, 8)

            Rectangle()
                .fill(.black)
                .frame(width: closedNotchWidth)

            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                Text("Connected")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.gray)
            }
            .frame(width: 92, alignment: .trailing)
            .padding(.trailing, 8)
        }
        .frame(height: height, alignment: .center)
        .background(alignment: .leading) {
            LinearGradient(
                colors: [.cyan.opacity(0.22), .green.opacity(0.14), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .blur(radius: 14)
            .opacity(0.8)
        }
    }

    @ViewBuilder
    private var deviceIcon: some View {
        if profile.id.hasPrefix("sony-") {
            SonyDeviceArtwork(address: device?.bluetoothAddress, profile: profile, isConnected: true, size: iconSize)
        } else if let imageAssetName = profile.imageAssetName,
           let image = NSImage(named: imageAssetName) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: profile.symbolName)
                .font(.system(size: iconSize * 0.72, weight: .semibold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
        }
    }
}
