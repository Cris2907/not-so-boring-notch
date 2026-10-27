import AppKit
import CoreBluetooth
import SonyHeadphonesKit
import SwiftUI

struct XM6ActivityView: View {
    @ObservedObject var manager: XM6Manager
    private var controller: HeadphonesController { manager.controller }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if manager.isConnected {
                noiseControls
                Divider().overlay(.white.opacity(0.12))
                XM6DetailsView(controller: controller)
            } else {
                connectionPrompt
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.black)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("XM6 headphone controls")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if !manager.isConnected && !manager.isConnecting { controller.refreshPairedDevices() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "headphones").accessibilityHidden(true)
            Text(controller.deviceName ?? manager.defaultDevice?.name ?? manager.rememberedDevice?.name ?? "WH-1000XM6")
                .font(.headline).lineLimit(1)
            if manager.isConnected {
                XM6BatteryView(battery: controller.battery)
            }
            Spacer(minLength: 0)
            if manager.isConnected {
                Button { controller.refreshState() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh headphone state")
                .help("Refresh headphone state")
            }
            if manager.isConnected || manager.isConnecting {
                Button(manager.isConnecting ? String(localized: "Cancel") : String(localized: "Disconnect")) {
                    manager.disconnect()
                }
            } else {
                Button("Connect") { manager.connect() }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var noiseControls: some View {
        HStack(spacing: 8) {
            ForEach(AmbientSoundMode.allCases, id: \.self) { mode in
                Button {
                    var state = controller.ambientSound ?? AmbientSoundState()
                    state.mode = mode
                    controller.setAmbientSound(state)
                } label: {
                    Text(mode.xm6Label)
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            .white.opacity(controller.ambientSound?.mode == mode ? 0.22 : 0.07),
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(controller.ambientSound?.mode == mode ? .isSelected : [])
                .help(mode.xm6Label)
            }
            if controller.ambientSound == nil {
                Text("Not reported").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var connectionPrompt: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if manager.isConnecting {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Connecting to your headphones…")
                    }
                } else {
                    Text(connectionMessage)
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if controller.lastError != nil {
                            Button("Retry") { manager.connect() }
                        }
                        Button("Bluetooth Settings") { XM6SystemSettings.openBluetooth() }
                        Button("Bluetooth Permission") { XM6SystemSettings.openPrivacy() }
                        Menu("Choose paired headphones") {
                            ForEach(controller.pairedDevices) { device in
                                Button(device.name) { manager.connect(to: device) }
                            }
                            if controller.pairedDevices.isEmpty {
                                Text("No paired devices")
                            }
                        }
                        .onAppear { controller.refreshPairedDevices() }
                        Button { controller.refreshPairedDevices() } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh paired devices")
                        .help("Refresh paired devices")
                    }
                    .controlSize(.small)
                    Text("Only WH-1000XM6 headphones are supported. You can select them manually if renamed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
    }

    private var connectionMessage: String {
        if CBManager.authorization == .denied || CBManager.authorization == .restricted {
            return String(localized: "Bluetooth access is disabled. Allow boring.notch in Bluetooth Privacy settings, then retry.")
        }
        return controller.lastError.map { String(localized: String.LocalizationValue($0)) }
            ?? String(localized: "Pair your WH-1000XM6 in Bluetooth settings, then connect. Headphone settings stay as they are.")
    }
}

private struct XM6DetailsView: View {
    @ObservedObject var controller: HeadphonesController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if controller.initialStateTimedOut {
                    Text("Some settings were not reported. Refresh to request them again.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if controller.ambientSound?.mode == .ambientSound {
                    ambientControls
                }
                soundControls
                equalizerControls
                behaviorControls
                deviceControls
            }
            .padding(.trailing, 6)
            .padding(.bottom, 8)
        }
    }

    private var ambientControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Ambient level")
                Slider(value: Binding(
                    get: { Double(controller.ambientSound?.level ?? 0) },
                    set: { value in
                        guard var state = controller.ambientSound else { return }
                        state.level = Int(value)
                        controller.setAmbientSound(state)
                    }
                ), in: 0...20, step: 1)
                .accessibilityLabel("Ambient sound level")
                Text("\(controller.ambientSound?.level ?? 0)")
                    .monospacedDigit().frame(width: 24)
                Toggle("Focus on Voice", isOn: Binding(
                    get: { controller.ambientSound?.focusOnVoice ?? false },
                    set: { value in
                        guard var state = controller.ambientSound else { return }
                        state.focusOnVoice = value
                        controller.setAmbientSound(state)
                    }
                ))
                .toggleStyle(.checkbox)
            }
        }
        .font(.caption)
    }

    private var soundControls: some View {
        HStack(spacing: 12) {
            Picker("Listening mode", selection: Binding<ListeningMode?>(
                get: { controller.listeningMode },
                set: { if let value = $0 { controller.setListeningMode(value) } }
            )) {
                if controller.listeningMode == nil { Text("Not reported").tag(nil as ListeningMode?) }
                ForEach(ListeningMode.allCases) { mode in
                    Text(LocalizedStringKey(mode.label)).tag(Optional(mode))
                }
            }
            if controller.listeningMode == .backgroundMusic {
                Picker("Room", selection: Binding<BGMRoomSize?>(
                    get: { controller.bgmRoomSize },
                    set: { if let value = $0 { controller.setBGMRoomSize(value) } }
                )) {
                    if controller.bgmRoomSize == nil { Text("Not reported").tag(nil as BGMRoomSize?) }
                    ForEach(BGMRoomSize.allCases) { room in
                        Text(LocalizedStringKey(room.label)).tag(Optional(room))
                    }
                }
            }
        }
        .controlSize(.small)
    }

    private var equalizerControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Equalizer").font(.caption.weight(.semibold))
                Spacer()
                Menu {
                    ForEach(EqualizerPreset.allCases) { preset in
                        Button(LocalizedStringKey(preset.label)) { controller.setEqualizerPreset(preset) }
                    }
                } label: {
                    Text(controller.equalizer.map { $0.preset.map { String(localized: String.LocalizationValue($0.label)) } ?? String(localized: "Personalized") } ?? String(localized: "Not reported"))
                }
                .fixedSize()
                .accessibilityLabel("Equalizer preset")
            }
            if controller.equalizer?.preset == .custom {
                customBands
            } else if let state = controller.equalizer, state.preset == nil {
                Text("A personalized preset is active. Choosing a preset replaces it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var bands: [Int] {
        guard let reported = controller.equalizer?.bands, reported.count == SonyCommands.defaultBandCount else {
            return Array(repeating: 0, count: SonyCommands.defaultBandCount)
        }
        return reported
    }

    private var customBands: some View {
        VStack(alignment: .leading, spacing: 6) {
            if controller.equalizer?.bands.count != SonyCommands.defaultBandCount {
                Text("Band levels not reported. Editing starts from flat.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 0) {
                ForEach(0..<SonyCommands.defaultBandCount, id: \.self) { index in
                    VStack(spacing: 3) {
                        Text(bands[index] > 0 ? "+\(bands[index])" : "\(bands[index])")
                            .monospacedDigit()
                        Slider(value: Binding(
                            get: { Double(bands[index]) },
                            set: { value in
                                var updated = bands
                                updated[index] = Int(value)
                                controller.setEqualizerBands(updated)
                            }
                        ), in: -6...6, step: 1)
                        .frame(width: 76)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 28, height: 82)
                        .accessibilityLabel(Text("Equalizer band \(index + 1)"))
                        .accessibilityValue(Text("\(bands[index])"))
                        Text("\(index + 1)").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
                }
            }
            HStack {
                Text("Low").foregroundStyle(.secondary)
                Spacer()
                Button("Reset to flat") {
                    controller.setEqualizerBands(Array(repeating: 0, count: SonyCommands.defaultBandCount))
                }
                .disabled(bands.allSatisfy { $0 == 0 } && controller.equalizer?.bands.count == SonyCommands.defaultBandCount)
                Spacer()
                Text("High").foregroundStyle(.secondary)
            }
            .font(.caption).controlSize(.small)
        }
    }

    private var behaviorControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                reportedToggle("Speak-to-Chat", value: controller.speakToChatEnabled, set: controller.setSpeakToChatEnabled)
                Spacer()
                reportedToggle("Pause when taken off", value: controller.pauseWhenTakenOff, set: controller.setPauseWhenTakenOff)
            }
            HStack(spacing: 12) {
                Picker("Sensitivity", selection: Binding<SpeakToChatSensitivity?>(
                    get: { controller.speakToChatConfig?.sensitivity },
                    set: { value in
                        guard let value, var config = controller.speakToChatConfig else { return }
                        config.sensitivity = value
                        controller.setSpeakToChatConfig(config)
                    }
                )) {
                    if controller.speakToChatConfig == nil { Text("Not reported").tag(nil as SpeakToChatSensitivity?) }
                    ForEach(SpeakToChatSensitivity.allCases) { value in
                        Text(LocalizedStringKey(value.label)).tag(Optional(value))
                    }
                }
                Picker("Resume audio", selection: Binding<SpeakToChatTimeout?>(
                    get: { controller.speakToChatConfig?.timeout },
                    set: { value in
                        guard let value, var config = controller.speakToChatConfig else { return }
                        config.timeout = value
                        controller.setSpeakToChatConfig(config)
                    }
                )) {
                    if controller.speakToChatConfig == nil { Text("Not reported").tag(nil as SpeakToChatTimeout?) }
                    ForEach(SpeakToChatTimeout.allCases) { value in
                        Text(LocalizedStringKey(value.label)).tag(Optional(value))
                    }
                }
            }
            .disabled(controller.speakToChatConfig == nil || controller.speakToChatEnabled != true)
            Picker("Automatic power off", selection: Binding<AutomaticPowerOffMode?>(
                get: { controller.automaticPowerOff },
                set: { if let value = $0 { controller.setAutomaticPowerOff(value) } }
            )) {
                if controller.automaticPowerOff == nil { Text("Not reported").tag(nil as AutomaticPowerOffMode?) }
                ForEach(AutomaticPowerOffMode.allCases) { value in
                    Text(LocalizedStringKey(value.label)).tag(Optional(value))
                }
            }
        }
        .controlSize(.small)
    }

    private func reportedToggle(_ label: LocalizedStringKey, value: Bool?, set: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 5) {
            Toggle(label, isOn: Binding(get: { value ?? false }, set: set))
                .toggleStyle(.checkbox).disabled(value == nil)
            if value == nil { Text("Not reported").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var deviceControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Connected devices").font(.caption.weight(.semibold))
            if let devices = controller.devices {
                if devices.isEmpty { Text("No connected devices").font(.caption).foregroundStyle(.secondary) }
                ForEach(devices) { device in
                    HStack {
                        Image(systemName: device.isPlayback ? "speaker.wave.2.fill" : "laptopcomputer.and.iphone")
                            .accessibilityHidden(true)
                        Text(device.name).lineLimit(1)
                        Spacer()
                        if device.isPlayback {
                            Text("Playing").foregroundStyle(.secondary)
                        } else if device.isConnected {
                            Button("Play here") { controller.switchPlayback(to: device) }
                                .accessibilityLabel(Text("Play from \(device.name)"))
                        } else {
                            Text("Not connected").foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption).controlSize(.small)
                }
            } else {
                Text("Not reported").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct XM6BatteryView: View {
    let battery: BatteryStatus?
    var body: some View {
        HStack(spacing: 3) {
            if battery?.isCharging == true {
                Image(systemName: "bolt.fill").font(.system(size: 10)).accessibilityHidden(true)
            }
            Text(battery.map { "\($0.level)%" } ?? "—")
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.system(size: 13, weight: .medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(battery.map {
            $0.isCharging ? String(localized: "Battery \($0.level) percent, charging") : String(localized: "Battery \($0.level) percent")
        } ?? String(localized: "Battery not reported"))
    }
}

struct XM6ChinView: View {
    @ObservedObject var manager: XM6Manager
    let minimal: Bool
    var body: some View {
        HStack(spacing: 6) {
            if !minimal {
                Text(manager.controller.ambientSound?.mode.xm6Abbreviation ?? "—")
                    .font(.system(size: 13, weight: .medium))
            }
            XM6BatteryView(battery: manager.controller.battery)
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "XM6, \(manager.controller.ambientSound?.mode.xm6Label ?? String(localized: "Noise mode not reported")), \(manager.controller.battery.map { String(localized: "Battery \($0.level) percent") } ?? String(localized: "Battery not reported"))"))
    }
}

struct XM6SettingsView: View {
    @ObservedObject var manager: XM6Manager
    var body: some View {
        Form {
            Section {
                HStack {
                    Picker("Default Bluetooth accessory", selection: Binding<String?>(
                        get: { manager.defaultDevice?.id },
                        set: { address in
                            manager.setDefaultDevice(manager.controller.pairedDevices.first { $0.id == address }
                                ?? manager.defaultDevice.flatMap { $0.id == address ? $0 : nil })
                        }
                    )) {
                        Text("Last connected or auto-detect").tag(nil as String?)
                        ForEach(manager.controller.pairedDevices) { device in
                            Text(device.name).tag(Optional(device.id))
                        }
                        if let device = manager.defaultDevice,
                           !manager.controller.pairedDevices.contains(where: { $0.id == device.id }) {
                            Text("\(device.name) (not currently paired)").tag(Optional(device.id))
                        }
                    }
                    Button { manager.controller.refreshPairedDevices() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh paired devices")
                    .help("Refresh paired devices")
                }
                Text("Treat this accessory as your XM6 headphones. The choice is saved for Connect and automatic reconnection; an active connection stays open until you disconnect.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Reconnect automatically", isOn: $manager.automaticReconnect)
                Text("Reconnect to your default accessory or last connected headphones on launch, wake, and headphone reconnection. Disconnect pauses this until Connect or the next app launch.")
                    .font(.caption).foregroundStyle(.secondary)
                if let device = manager.rememberedDevice {
                    LabeledContent("Remembered headphones", value: device.name)
                }
                Button("Bluetooth Settings") { XM6SystemSettings.openBluetooth() }
                Button("Bluetooth Permission") { XM6SystemSettings.openPrivacy() }
            } header: { Text("Connection") }
            Section {
                Toggle("Protocol logging", isOn: Binding(
                    get: { manager.controller.protocolLoggingEnabled },
                    set: { manager.controller.protocolLoggingEnabled = $0 }
                ))
                Text("Off by default. Records Bluetooth protocol traffic inside boring.notch’s application container for troubleshooting.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Show protocol log") {
                    if let url = manager.controller.protocolLogURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                .disabled(manager.controller.protocolLogURL.map { !FileManager.default.fileExists(atPath: $0.path) } ?? true)
            } header: { Text("Diagnostics") }
        }
        .formStyle(.grouped)
        .onAppear { manager.controller.refreshPairedDevices() }
    }
}

private enum XM6SystemSettings {
    static func openBluetooth() {
        open("x-apple.systempreferences:com.apple.BluetoothSettings")
    }
    static func openPrivacy() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")
    }
    private static func open(_ path: String) {
        if let url = URL(string: path) { NSWorkspace.shared.open(url) }
    }
}

extension AmbientSoundMode {
    var xm6Label: String {
        switch self {
        case .off: String(localized: "Off")
        case .noiseCancelling: String(localized: "Noise Cancelling")
        case .ambientSound: String(localized: "Ambient")
        }
    }
    var xm6Abbreviation: String {
        switch self {
        case .off: String(localized: "Off")
        case .noiseCancelling: String(localized: "NC")
        case .ambientSound: String(localized: "AMB")
        }
    }
}
