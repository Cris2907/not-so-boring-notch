# Bluetooth Headphone Notifications

This feature shows a short closed-notch animation when Bluetooth headphones, such as AirPods, become the active macOS audio output.

The implementation is intentionally split into two layers:

1. CoreAudio detects the active output device.
2. IOBluetooth enriches that active audio device with paired-device details when available.

CoreAudio remains the source of truth. The app does not show the animation for every Bluetooth connection; it shows it when a Bluetooth audio device becomes the system output.

## Runtime Flow

1. `BluetoothAudioManager.shared.start()` runs during `applicationDidFinishLaunching` in `boringNotch/boringNotchApp.swift`.
2. `BluetoothAudioManager` listens for `kAudioHardwarePropertyDefaultOutputDevice` changes on the CoreAudio system object.
3. When the default output changes, the manager reads:
   - device name
   - transport type
   - manufacturer, when exposed
   - model UID, when exposed
4. If the transport is Bluetooth, or can be matched to a connected paired Bluetooth device, the manager builds a `BluetoothAudioDevice`.
5. `BluetoothHeadphoneProfileStore` maps that device to the best available profile.
6. The manager calls `BoringViewCoordinator.shared.toggleSneakPeek(status:type:duration:icon:)` with `.bluetooth`.
7. `ContentView` detects the `.bluetooth` sneak peek and renders `BluetoothDeviceActivity` in the closed notch.
8. The coordinator hides the transient notification after the configured duration.

## Trigger Behavior

The animation should trigger when:

- AirPods or other Bluetooth headphones connect and macOS automatically switches output to them.
- The user manually selects connected Bluetooth headphones as the system output.

The animation should not trigger when:

- A Bluetooth device connects but does not become the active output.
- Built-in speakers become active.
- USB or other non-Bluetooth output devices become active.
- The output device repeatedly reports the same identity within the debounce window.

## Main Files

- `boringNotch/managers/BluetoothAudioManager.swift`
  - Owns CoreAudio output observation.
  - Registers optional IOBluetooth connect/disconnect notifications.
  - Publishes the active notification device and profile.
  - Debounces duplicate notifications.

- `boringNotch/models/BluetoothHeadphoneProfile.swift`
  - Defines `BluetoothAudioDevice`.
  - Defines `BluetoothHeadphoneProfile`.
  - Defines `BluetoothHeadphoneProfileStore`, including profile matching and fallback behavior.

- `boringNotch/components/Live activities/BluetoothDeviceActivity.swift`
  - Renders the compact closed-notch notification.
  - Uses a product asset when available.
  - Falls back to SF Symbols when no asset exists.

- `boringNotch/ContentView.swift`
  - Observes `BluetoothAudioManager.shared`.
  - Expands the closed-notch chin width for Bluetooth notifications.
  - Keeps Bluetooth notifications out of the volume/brightness HUD renderers.

- `boringNotch/BoringViewCoordinator.swift`
  - Adds `.bluetooth` as a `SneakContentType`.
  - Reuses existing timed sneak-peek show/hide behavior.

- `boringNotch/components/Settings/SettingsView.swift`
  - Adds Media settings for Bluetooth headphone notifications and device matching.

## Profile Matching

Profiles are matched in this order:

1. Saved model assignment for the canonical Bluetooth address.
2. Model UID (including exact Sony models), when macOS exposes it.
3. Model-specific Sony name match, with case/separator normalization and model boundaries.
4. Existing manufacturer/name family profiles, then the generic fallback.

The catalog retains AirPods, AirPods Pro, AirPods Max, Beats, Bose QuietComfort,
and generic Sony profiles. It also includes all 14 Sony models with renders:
WH-1000XM2/3/4/5/6, WH-CH520, WH-CH720N, WH-XB900N, WH-XB910N,
MDR-XB950BT, WF-1000XM4/5, WF-C700N, and LinkBuds S.

Settings → Media → Bluetooth headphones lists paired devices and lets users
choose a model or Automatic. Assignments use the `bluetoothHeadphoneModelAssignments`
UserDefaults dictionary: canonical twelve-digit lowercase Bluetooth address → profile ID.
Automatic removes the assignment; unknown saved model IDs fall back to automatic matching.
Assignments change artwork only, never protocol compatibility or connection preferences.

CoreAudio device UIDs supply addresses when available. Otherwise, only a unique
normalized name among connected paired devices may establish an association.
Ambiguous names and conflicting addresses never inherit another device's assignment.
Settings discovery reads the paired-device registry without connecting headphones.

The XM6 header uses its own connected RFCOMM device name/address and the same
resolver. It displays the resolved Sony render independently of the active audio output.
The XM6 actions menu also offers Illustration → Automatic or any of the 14 Sony
models, using the same saved address assignment as Media settings. Assignment edits update artwork without replaying the
connection notification. Collapsed activity artwork and notification timing stay unchanged.

## Image Assets

Profiles can specify an optional `imageAssetName`, such as `headphones-airpods-pro`.

Images should live in `boringNotch/Assets.xcassets` using normal `.imageset` folders. The current UI does not require these assets to exist. If an image is missing, `BluetoothDeviceActivity` falls back to the profile's SF Symbol.

The 14 Sony renders are bundled as transparent PNGs copied from SonyBridge; attribution is included in `THIRD_PARTY_LICENSES`. Missing artwork continues to use the existing symbol fallback.

## Settings

The Media settings page includes:

- Show headphone connection animation
- Use Bluetooth device matching

The first toggle gates the notch animation. The second controls IOBluetooth enrichment. CoreAudio output tracking remains the safer baseline because it identifies the active audio device directly.

## Permissions And Frameworks

The app declares:

- `com.apple.security.device.bluetooth` in `boringNotch/boringNotch.entitlements`
- `NSBluetoothAlwaysUsageDescription` in `boringNotch/Info.plist`

The project links `IOBluetooth.framework` but does not embed it.

## Limitations

- Battery levels are not implemented.
- Case/left/right AirPods battery details are not expected from this implementation.
- The notification is tied to active audio output, not every paired Bluetooth connection.
- Some devices may report transport as wireless rather than Bluetooth. IOBluetooth matching helps with that case, but real hardware may still reveal devices that need profile or classification tweaks.
- Product image quality depends on adding matching assets to the asset catalog.

## Validation

Build:

```sh
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build
```

Test:

```sh
xcodebuild test -project boringNotch.xcodeproj -scheme boringNotch -destination 'platform=macOS'
```

Verify the Bluetooth entitlement in a built app:

```sh
codesign -d --entitlements :- /path/to/boringNotch.app
```

Manual test:

1. Launch boring.notch.
2. Enable `Show headphone connection animation`.
3. Connect AirPods or another Bluetooth headset.
4. Confirm macOS switches output to that device, or select it manually.
5. Confirm the closed-notch Bluetooth animation appears once with the device name.