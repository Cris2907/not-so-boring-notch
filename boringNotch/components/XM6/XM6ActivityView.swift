import AppKit
import CoreBluetooth
import SonyHeadphonesKit
import SwiftUI

struct XM6ActivityView: View {
    @ObservedObject var manager: XM6Manager
    @ObservedObject private var identities = SonyDeviceIdentityStore.shared
    @ObservedObject private var modelAssignments: HeadphoneModelAssignments
    private let artwork: SonyArtworkStore
    private var controller: HeadphonesController { manager.controller }
    @AppStorage("xm6.preferredTransparencyLevel") private var preferredTransparencyLevel = 20
    @AppStorage("xm6.playModeChangeSounds") private var playsModeChangeSounds = true
    @AppStorage("xm6.duckModeChangeAudio") private var ducksModeChangeAudio = true

    private var headerDevice: BluetoothAudioDevice? {
        if controller.deviceAddress != nil {
            return BluetoothAudioDevice(audioObjectID: 0, name: controller.deviceName ?? "", manufacturer: nil,
                modelUID: controller.identity.modelName, transportType: 0, bluetoothAddress: controller.deviceAddress,
                isBluetooth: true, detectedAt: .distantPast)
        }
        // An identified active Sony audio device can show its render without enabling XM6 controls.
        if let device = identities.activeDevice, identities.identity(for: device.bluetoothAddress)?.modelName != nil { return device }
        return nil
    }
    private var headerAddress: String? { headerDevice?.bluetoothAddress }
    private var headerIdentity: SonyDeviceIdentity? {
        if controller.deviceAddress != nil { return controller.identity }
        return identities.identity(for: headerAddress)
    }
    private var headerConnected: Bool {
        controller.deviceAddress != nil ? controller.connectionState == .connected : headerIdentity?.modelName != nil
    }
    private var headerProfile: BluetoothHeadphoneProfile {
        let device = headerDevice ?? BluetoothAudioDevice(audioObjectID: 0, name: controller.deviceName ?? "", manufacturer: nil,
            modelUID: nil, transportType: 0, bluetoothAddress: nil, isBluetooth: true, detectedAt: .distantPast)
        if modelAssignments.assignedProfileID(for: device.bluetoothAddress) != nil {
            return modelAssignments.profile(for: device)
        }
        return identities.profile(for: device)
    }

    @MainActor
    init(manager: XM6Manager, modelAssignments: HeadphoneModelAssignments = .shared,
         identities: SonyDeviceIdentityStore? = nil, artwork: SonyArtworkStore? = nil) {
        self.manager = manager
        self.modelAssignments = modelAssignments
        self.identities = identities ?? .shared
        self.artwork = artwork ?? .shared
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if manager.isConnected {
                noiseControls
                XM6DetailsView(controller: controller)
            } else {
                connectionPrompt
            }
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("XM6 headphone controls")
        .onChange(of: playsModeChangeSounds) { _, enabled in
            if !enabled { XM6ModeChangeSound.shared.stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if !manager.isConnected && !manager.isConnecting { controller.refreshPairedDevices() }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            SonyDeviceArtwork(address: headerAddress, profile: headerProfile,
                              isConnected: headerConnected, size: 112, identities: identities, artwork: artwork)
            VStack(alignment: .leading, spacing: 8) {
                Text(headerIdentity?.modelName ?? controller.deviceName ?? manager.defaultDevice?.name ?? manager.rememberedDevice?.name ?? "WH-1000XM6")
                    .font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(manager.isConnected ? "Connected" : manager.isConnecting ? "Connecting controls…" : headerConnected ? "Audio connected · Controls unavailable" : "Not connected")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    if manager.isConnected {
                        Image(systemName: batterySymbol).foregroundStyle(.secondary).accessibilityHidden(true)
                        XM6BatteryView(battery: controller.battery)
                        Spacer(minLength: 0)
                        Menu {
                            Button("Refresh headphone state", systemImage: "arrow.clockwise") { controller.refreshState() }
                            illustrationMenu
                            Toggle("Play mode-change sounds", isOn: $playsModeChangeSounds)
                            Divider()
                            Button("Disconnect", systemImage: "bolt.horizontal.circle") { manager.disconnect() }
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.system(size: 16))
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel("Headphone actions")
                    } else {
                        Button(manager.isConnecting ? "Cancel" : "Connect") {
                            if manager.isConnecting { manager.disconnect() } else { manager.connect() }
                        }.controlSize(.small)
                    }
                }
            }
        }
        .frame(height: 112)
    }

    private var illustrationMenu: some View {
        Menu("Illustration") {
            Button {
                if let address = controller.deviceAddress { modelAssignments.assign(nil, to: address) }
            } label: {
                if modelAssignments.assignedProfileID(for: controller.deviceAddress) == nil {
                    Label("Automatic", systemImage: "checkmark")
                } else { Text("Automatic") }
            }
            Divider()
            ForEach(BluetoothHeadphoneProfileStore.sonyProfiles) { profile in
                Button {
                    if let address = controller.deviceAddress { modelAssignments.assign(profile.id, to: address) }
                } label: {
                    if modelAssignments.assignedProfileID(for: controller.deviceAddress) == profile.id {
                        Label(profile.displayName, systemImage: "checkmark")
                    } else { Text(profile.displayName) }
                }
            }
        }
        .disabled(BluetoothAddress.canonical(controller.deviceAddress) == nil)
    }

    private var batterySymbol: String {
        guard let battery = controller.battery else { return "battery.0percent" }
        switch battery.level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var noiseControls: some View {
        XM6NoiseModeSelector(selection: controller.ambientSound?.mode) { mode in
            guard manager.isConnected, mode != controller.ambientSound?.mode else { return }
            var state = controller.ambientSound ?? AmbientSoundState()
            state.mode = mode
            if mode == .ambientSound { state.level = max(0, min(20, preferredTransparencyLevel)) }
            controller.setAmbientSound(state)
            if playsModeChangeSounds { XM6ModeChangeSound.shared.play(mode, duckPlayback: ducksModeChangeAudio) }
        }
    }

    private var connectionPrompt: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if manager.isConnecting {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 8) {
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
        .preservesNotchContentScrolling()
    }

    private var connectionMessage: String {
        if CBManager.authorization == .denied || CBManager.authorization == .restricted {
            return String(localized: "Bluetooth access is disabled. Allow boring.notch in Bluetooth Privacy settings, then retry.")
        }
        if let identity = headerIdentity, let model = identity.modelName, !identity.supportsXM6Controls {
            return "Detected \(model). Headphone controls currently support WH-1000XM6 only."
        }
        return controller.lastError.map { String(localized: String.LocalizationValue($0)) }
            ?? String(localized: "Pair your WH-1000XM6 in Bluetooth settings, then connect. Headphone settings stay as they are.")
    }
}

/// The extension uses its RFCOMM device identity, never the current audio output.
struct XM6DeviceArtwork: View {
    let profile: BluetoothHeadphoneProfile
    let isConnected: Bool

    var body: some View {
        Group {
            if isConnected, BluetoothHeadphoneProfileStore.sonyProfiles.contains(where: { $0.id == profile.id }),
               let asset = profile.imageAssetName, let image = NSImage(named: asset) {
                Image(nsImage: image).resizable().scaledToFit().padding(1)
            } else {
                Image(systemName: "headphones").font(.system(size: 17, weight: .medium))
            }
        }
    }
}

struct XM6DetailsView: View {
    @AppStorage("xm6.preferredTransparencyLevel") private var preferredTransparencyLevel = 20
    @ObservedObject var controller: HeadphonesController

    @State private var showsMoreSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(controller: HeadphonesController, showsMoreSettings: Bool = false) {
        self.controller = controller
        _showsMoreSettings = State(initialValue: showsMoreSettings)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                if controller.initialStateTimedOut {
                    Label("Some settings are unavailable. Refresh to try again.", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 8) {
                    soundControls
                    equalizerControls
                }
                behaviorControls
                DisclosureGroup(isExpanded: $showsMoreSettings) {
                    VStack(alignment: .leading, spacing: 12) {
                        if controller.ambientSound?.mode == .ambientSound { ambientControls }
                        if controller.listeningMode == .backgroundMusic { roomControls }
                        if controller.equalizer?.preset == .custom {
                            Text("Custom equalizer").font(.caption.weight(.medium))
                            customBands
                        }
                        powerControls
                        deviceControls
                    }
                    .padding(.top, 8)
                } label: {
                    Text(controller.equalizer?.preset == .custom ? "More settings · Custom EQ" : "More settings")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .tint(.secondary)
            }
            .padding(.bottom, 4)
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
        .preservesNotchContentScrolling()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: controller.speakToChatEnabled)
    }

    private var ambientControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Ambient level")
                Slider(value: Binding(
                    get: { Double(controller.ambientSound?.level ?? 0) },
                    set: { value in
                        guard var state = controller.ambientSound else { return }
                        state.level = max(0, min(20, Int(value)))
                        preferredTransparencyLevel = state.level
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
                .toggleStyle(.switch).controlSize(.mini).tint(.secondary)
            }
        }
        .font(.caption)
    }

    private var soundControls: some View {
        XM6SettingRow(title: "Listening mode", systemImage: "waveform") {
            Picker("Listening mode", selection: Binding<ListeningMode?>(
                get: { controller.listeningMode },
                set: { if let value = $0 { controller.setListeningMode(value) } }
            )) {
                if controller.listeningMode == nil { Text("Not reported").tag(nil as ListeningMode?) }
                ForEach(ListeningMode.allCases) { mode in
                    Text(LocalizedStringKey(mode.label)).tag(Optional(mode))
                }
            }
            .labelsHidden().pickerStyle(.menu)
        }
    }

    private var roomControls: some View {
        Picker("Room", selection: Binding<BGMRoomSize?>(
            get: { controller.bgmRoomSize },
            set: { if let value = $0 { controller.setBGMRoomSize(value) } }
        )) {
            if controller.bgmRoomSize == nil { Text("Not reported").tag(nil as BGMRoomSize?) }
            ForEach(BGMRoomSize.allCases) { room in
                Text(LocalizedStringKey(room.label)).tag(Optional(room))
            }
        }
        .controlSize(.small)
    }

    private var equalizerControls: some View {
        XM6SettingRow(title: "Equalizer", systemImage: "slider.vertical.3") {
            Menu {
                ForEach(EqualizerPreset.allCases) { preset in
                    Button {
                        controller.setEqualizerPreset(preset)
                    } label: {
                        if controller.equalizer?.preset == preset {
                            Label(LocalizedStringKey(preset.label), systemImage: "checkmark")
                        } else { Text(LocalizedStringKey(preset.label)) }
                    }
                }
            } label: {
                Text(controller.equalizer.map { $0.preset.map { String(localized: String.LocalizationValue($0.label)) } ?? String(localized: "Personalized") } ?? String(localized: "Not reported"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityLabel("Equalizer preset")
            .help("Choosing a preset replaces the current equalizer. Custom band controls are in More settings.")
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                reportedToggle("Speak-to-Chat", value: controller.speakToChatEnabled, set: controller.setSpeakToChatEnabled)
                Spacer()
                reportedToggle("Pause when taken off", value: controller.pauseWhenTakenOff, set: controller.setPauseWhenTakenOff)
            }
            if controller.speakToChatEnabled == true {
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
            }
        }
        .controlSize(.mini)
        .font(.system(size: 11))
        .padding(8)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Smart features")
    }

    private var powerControls: some View {
        Picker("Automatic power off", selection: Binding<AutomaticPowerOffMode?>(
            get: { controller.automaticPowerOff },
            set: { if let value = $0 { controller.setAutomaticPowerOff(value) } }
        )) {
            if controller.automaticPowerOff == nil { Text("Not reported").tag(nil as AutomaticPowerOffMode?) }
            ForEach(AutomaticPowerOffMode.allCases) { value in
                Text(LocalizedStringKey(value.label)).tag(Optional(value))
            }
        }
        .controlSize(.small)
    }

    private func reportedToggle(_ label: LocalizedStringKey, value: Bool?, set: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 5) {
            Toggle(label, isOn: Binding(get: { value ?? false }, set: set))
                .toggleStyle(.switch).controlSize(.mini).tint(.secondary).disabled(value == nil)
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

private struct XM6SettingRow<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                content
            }
        }
        .font(.system(size: 12, weight: .medium))
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

/// A single sliding selection capsule; native buttons retain keyboard and
/// accessibility behavior while dragging commits only once on finger lift.
struct XM6NoiseModeSelector: View {
    let selection: AmbientSoundMode?
    let select: (AmbientSoundMode) -> Void
    @GestureState private var draggedIndex: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    private let modes: [AmbientSoundMode] = [.off, .noiseCancelling, .ambientSound]

    private var selectedIndex: Int? { draggedIndex ?? modes.firstIndex(where: { $0 == selection }) }

    static func index(at x: CGFloat, width: CGFloat, isRightToLeft: Bool = false) -> Int {
        let index = min(2, max(0, Int((min(max(x, 0), max(width - 1, 0)) / max(width, 1)) * 3)))
        return isRightToLeft ? 2 - index : index
    }

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { geometry in
                let width = geometry.size.width / 3
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.06))
                    Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                    if let index = selectedIndex {
                        Capsule()
                            .fill(.primary.opacity(0.16))
                            .overlay(Capsule().strokeBorder(.primary.opacity(0.18), lineWidth: 0.5))
                            .frame(width: width - 4, height: 28)
                            .position(x: CGFloat(layoutDirection == .rightToLeft ? 2 - index : index) * width + width / 2, y: 16)
                            .allowsHitTesting(false)
                    }
                    HStack(spacing: 0) {
                        ForEach(Array(modes.enumerated()), id: \.offset) { index, mode in
                            Button { select(mode) } label: {
                                Image(systemName: mode.xm6Symbol)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(selectedIndex == index ? mode.xm6SelectedColor : Color.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(mode.xm6Label)
                            .accessibilityAddTraits(selection == mode ? .isSelected : [])
                            .help(mode.xm6Label)
                        }
                    }
                }
                .simultaneousGesture(DragGesture(minimumDistance: 8)
                    .updating($draggedIndex) { value, index, _ in
                        index = Self.index(at: value.location.x, width: geometry.size.width,
                                           isRightToLeft: layoutDirection == .rightToLeft)
                    }
                    .onEnded { value in
                        select(modes[Self.index(at: value.location.x, width: geometry.size.width,
                                                isRightToLeft: layoutDirection == .rightToLeft)])
                    })
            }
            .frame(height: 32)
            HStack(spacing: 0) {
                ForEach(modes, id: \.self) { mode in
                    Text(mode.xm6Label)
                        .font(.system(size: 10, weight: selection == mode ? .medium : .regular))
                        .foregroundStyle(selection == mode ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Noise control")
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: selectedIndex)
    }
}

@MainActor
final class XM6ModeChangeSound {
    static let shared = XM6ModeChangeSound()
    private var currentSound: NSSound?
    private var restoreTask: Task<Void, Never>?
    private var operation: Task<Void, Never>?
    private var generation = 0
    private let ducker = XM6PlaybackDucker()
    private init() {}

    func prepareForTermination() async {
        stop()
        await operation?.value
    }

    static func resourceName(for mode: AmbientSoundMode) -> String {
        switch mode {
        case .off: "off"
        case .noiseCancelling: "noise-cancelling"
        case .ambientSound: "ambient"
        }
    }

    func play(_ mode: AmbientSoundMode, duckPlayback: Bool = false) {
        guard let url = Bundle.main.url(forResource: Self.resourceName(for: mode), withExtension: "wav",
                                        subdirectory: "NoiseControlSounds"),
              let sound = NSSound(contentsOf: url, byReference: true) else { return }
        generation += 1
        let token = generation
        restoreTask?.cancel()
        currentSound?.stop()
        let previous = operation
        // Serialize async player commands, including cleanup after rapid changes.
        operation = Task { @MainActor in
            await previous?.value
            guard token == self.generation else { return }
            let target = duckPlayback ? MusicManager.shared.modeChangeDuckingTarget() : nil
            await self.ducker.begin(target)
            guard token == self.generation else { await self.ducker.end(); return }
            self.currentSound = sound
            sound.volume = 0.35
            guard sound.play() else { await self.ducker.end(); self.currentSound = nil; return }
            self.restoreTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(sound.duration + 0.1))
                guard !Task.isCancelled, let self, token == self.generation else { return }
                self.stop()
            }
        }
    }

    func stop() {
        generation += 1
        restoreTask?.cancel()
        restoreTask = nil
        currentSound?.stop()
        currentSound = nil
        let previous = operation
        operation = Task { @MainActor in
            await previous?.value
            await self.ducker.end()
        }
    }
}

/// A lease on the original player's volume, independent of the system output.
@MainActor
final class XM6PlaybackDucker {
    static let factor = 0.75
    struct Target {
        let id: String
        let read: @MainActor () async -> Double?
        let write: @MainActor (Double) async -> Void
    }
    private var saved: (target: Target, original: Double, applied: Double)?
    var isDucking: Bool { saved != nil }

    func begin(_ target: Target?) async {
        if let saved, saved.target.id == target?.id { return }
        await end()
        guard let target, let original = await target.read(), original.isFinite,
              original > 0, original <= 1 else { return }
        let requested = original * Self.factor
        saved = (target, original, requested)
        await target.write(requested)
        // Confirm application and account for a player's integer volume steps.
        guard let applied = await target.read() else { return }
        guard applied.isFinite, abs(applied - requested) <= 0.011, applied < original else {
            saved = nil
            return
        }
        saved = (target, original, applied)
    }

    func end() async {
        guard let previous = saved else { return }
        saved = nil
        guard let current = await previous.target.read(), abs(current - previous.applied) < 0.005 else { return }
        await previous.target.write(previous.original)
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
    @AppStorage("xm6.playModeChangeSounds") private var playsModeChangeSounds = true
    @AppStorage("xm6.duckModeChangeAudio") private var ducksModeChangeAudio = true
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
            Section {
                Toggle("Play mode-change sounds", isOn: $playsModeChangeSounds)
                Toggle("Lower playback during mode-change sounds", isOn: $ducksModeChangeAudio)
                    .disabled(!playsModeChangeSounds)
                Text("Lowers the playing app’s volume while the chime stays at its normal level. Supports Music, Spotify, and the connected YouTube Music player.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Noise control feedback") }
        }
        .formStyle(.grouped)
        .onAppear { manager.controller.refreshPairedDevices() }
        .onChange(of: playsModeChangeSounds) { _, enabled in
            if !enabled { XM6ModeChangeSound.shared.stop() }
        }
        .onChange(of: ducksModeChangeAudio) { _, enabled in
            if !enabled { XM6ModeChangeSound.shared.stop() }
        }
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
    var xm6SelectedColor: Color {
        switch self {
        case .off: .green
        case .noiseCancelling: .red
        case .ambientSound: .blue
        }
    }
    var xm6Symbol: String {
        switch self {
        case .off: "speaker.slash"
        case .noiseCancelling: "waveform.slash"
        case .ambientSound: "ear"
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
