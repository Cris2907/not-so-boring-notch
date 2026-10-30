# Sony identity protocol and notch integration

Verified from decoded Sound Connect 13.3.0 bytecode. These are read-only device-information requests. No headphones were contacted during this analysis.

## Connected identification

Both MDR protocol generations examined use the same device-information payload opcodes and inquiry types:

| Information | Request payload | Reply payload |
| --- | --- | --- |
| Model name | `04 01` | `05 01 <byte-length> <model-name bytes>` |
| Firmware | `04 02` | `05 02 <byte-length> <version bytes>` |
| Series and color | `04 03` | `05 03 <series byte> <color byte>` |

These are payloads, not complete RFCOMM packets. They must pass through the existing framing, escaping, checksum, sequence-number, ACK, and connection-initialization machinery. Send them on the device's normal MDR command table, not the peripheral table.

Evidence:

- V1 `Command.CONNECT_GET_DEVICE_INFO = 0x04`, `CONNECT_RET_DEVICE_INFO = 0x05`; `DeviceInfoInquiredType` assigns model name `0x01`, firmware `0x02`, series/color `0x03`.
- V1 `tm0.k.f()` serializes the request. `tm0.y1$e` decodes the length-prefixed model name; `tm0.y1$f` reads the series at payload offset 2 and color at offset 3.
- V2 `Command` uses the same `0x04/0x05` values, and `connect.param.DeviceInfoType` uses the same inquiry codes.
- V2 `in0.b$b.f()` constructs the two-byte request. `in0.i$b` validates the model-name length, and `in0.i.g()` decodes it. `in0.j$b` validates a four-byte series/color response; `in0.j.e()` reads color at offset 3 and `in0.j.f()` reads series at offset 2.
- The series byte is a protocol series enum. Do not assume it is the catalog's `model_id` or a unique model number.

Implementations must reject truncated or inconsistent lengths, unknown reply types, and stale replies from an earlier connection. Preserve raw color values so future colors do not silently become black.

## Artwork lookup

The production GraphQL endpoint is `https://v1.api.data-gateway.seeds.services/graphql`. The Android client supplies an application client key via `x-api-key`; this inspection used the identifier already distributed in the APK's native `libcloudmodelinfo.so`, without account credentials. That identifier is not copied into these artifacts or the notch application.

The read-only `HPC.getAllCloudModelInfos` query succeeded with HTTP 200 and returned 252 model/color entries. See `production-model-catalog.json`.

The connected-device lookup uses **model name + model color**, with Sony's own default-color fallback. The returned fields include `sca_image_image_url` and `sca_anime_image_url`. Empty animation URLs are meaningful: some models have only a static image in this catalog.

The downloaded animation path was independently verified to use the `com.github.penfeizhou.animation.apng` decoder. Downloaded samples are actual 720 × 720 APNGs with roughly 143–150 frames and a 5-second timeline; metadata for each file is in `renders/index.json`.

## Discovery before a control connection

BLE discovery can recognize Sony manufacturer data (`0x012D`) and parse model ID/model-number/color data from supported advertisement formats. The catalog maps those identifiers to model names. This is a separate option from the connected queries above.

Advertisement layouts vary by packet version. Matching a BLE peripheral to a particular paired macOS audio device also requires care; an advertisement alone is not proof that it belongs to the selected audio output. The connected RFCOMM query is the more direct first integration for a device whose address is already known.

## Fit with the current notch code

Current code inspected directly:

- `Packages/SonyHeadphonesKit/Sources/SonyHeadphonesKit/HeadphonesController.swift` already manages Sony connection initialization, sequence numbers, ACKs, and published state.
- `.../Protocol/SonyMessage.swift` already encodes/decodes Sony frames.
- `.../Protocol/Opcodes.swift` currently has no model-name/series-color inquiry API.
- `boringNotch/models/BluetoothHeadphoneProfile.swift` currently resolves Sony profiles from model metadata or name patterns, with address-based manual assignments.
- `boringNotch/managers/BluetoothAudioManager.swift` associates the audio output with a Bluetooth device and chooses its notification profile.

Proposed integration:

1. Add read-only identity requests and defensive reply decoding to SonyHeadphonesKit.
2. Publish model name, series, and color as session state; clear them on disconnect.
3. Associate the result with the same canonical Bluetooth address as the active audio device. Keep an explicit user assignment authoritative.
4. Select the profile by the reported model, so renaming the Bluetooth device does not hide its identity.
5. Resolve artwork from a bundled catalog snapshot/local cache and render APNG frames using macOS ImageIO or another APNG-capable native player. Preserve frame durations and respect reduced-motion preferences. Do not rely on a static first-frame image: these samples start blank.
6. Test query responses, unsupported firmware/timeouts, reconnects, and renamed devices on actual headphones before enabling automatic identification broadly.

No notch source changes, automatic Bluetooth probes, or hardware verification were performed in this investigation. The live catalog and downloaded render files were verified; the identity packet layouts were verified statically against the APK.
