# XM6 headphone extension

XM6 is a built-in notch activity (`builtin.xm6`). Open its tab and click Connect
after pairing WH-1000XM6 headphones in macOS Bluetooth settings. If renamed, choose
them from the paired-device menu. Connecting reads the existing settings; it never
sets a startup noise mode, ambient level, EQ, or behavior preference.

In Settings → Extensions → XM6, choose a **Default Bluetooth accessory** from
paired devices to use even if the headphones have been renamed. This preference
is saved immediately and takes priority for Connect and automatic reconnection.
A one-time connection to another accessory does not replace the default. Changing
the default leaves an active connection open until disconnected. Select **Last
connected or auto-detect** to clear the explicit preference and restore the
previous behavior. A saved accessory that is no longer paired remains visible
in the selector so the preference can be changed or cleared.

The header and noise-mode buttons stay visible while detailed controls scroll.
The tab includes ambient level and voice focus, listening mode and BGM room size,
EQ presets and ten custom bands, Speak-to-Chat, wearing detection, automatic power
off, and multipoint playback selection. Changes made on the headphones or in
another companion app are reflected through protocol notifications.

Only successful connections are remembered automatically. An explicitly selected
default can also be used before the first successful connection. Automatic
reconnection defaults on and runs on launch, wake, and the preferred device's
Bluetooth connection notification. A manual Disconnect pauses this until Connect
or the next app launch. Disabling the extension stops its monitor and connection;
closing the tab does not. Sleep closes the control channel, and wake reconnects
when allowed. Connection attempts have finite deadlines and one silent retry.

The connected chin shows noise mode and battery (108-point content width), or
battery alone when sharing the notch (44 points). It disappears on disconnect.
The standard Extensions settings independently control enablement and chin
visibility. XM6 configuration contains automatic reconnection and opt-in logging.

## Architecture

`XM6Activity` adapts a shared `XM6Manager` to the normal activity registry. The
manager owns one `HeadphonesController` across all displays and observes the
existing enablement store. Its Bluetooth notifications do not depend on the
generic headphone popup preference or the selected audio output.

`Packages/SonyHeadphonesKit` vendors only the MIT-licensed library from Rui
Martins' XM6 Control; the original `xm6-control` checkout is untouched and is not
a build dependency. The package exports its library and uses an injectable
transport factory, paired-device provider, and session deadlines. Every attempt
gets a new transport and generation token. Ending a session clears state, queued
writes, and timers. Rapid EQ writes replace unsent curves; choosing a preset
cancels pending custom curves. A missing ACK ends the session rather than
advancing an unsafe protocol sequence.

Missing reports show “Not reported”; unknown EQ preset codes show “Personalized”.
Combined settings whose other values are unknown stay disabled until reported.
Selecting Custom without reported bands explicitly starts from flat. The noise
buttons can send an explicit selection before the initial state arrives.

Logs are off by default and perform no file writes until enabled. Their path is
the host app's Application Support/boring.notch/XM6/protocol.log, inside its
container for sandboxed builds. Logs contain raw protocol traffic and device
names/addresses; they stay local and rotate at approximately 2 MB.

## Validation

Package tests use fake transports; app tests use an isolated preferences suite
and fake connection monitor. Rendered expanded and chin previews are retained as
XCTest attachments. No Bluetooth commands are sent by these tests.

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path Packages/SonyHeadphonesKit
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project boringNotch.xcodeproj -scheme boringNotch -destination 'platform=macOS' -parallel-testing-enabled NO
```

Physical XM6 testing is still needed for firmware-specific responses, charging,
real multipoint playback, Bluetooth permission recovery, and sleep/wake. Manual
review should also cover scrolling, keyboard/VoiceOver, Reduce Motion, multiple
displays, physical and simulated notches, and concurrent chin providers. The
standalone XM6 app should be closed during hardware checks because the headset
may accept only one Sony control channel at a time.
