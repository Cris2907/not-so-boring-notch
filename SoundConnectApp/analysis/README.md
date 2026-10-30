# Sony Sound Connect APK inspection

Package inspected: `com.sony.songpal.mdr`, Sound Connect **13.3.0**, version code `130305109`, from `../base.apk` and all included configuration APKs. Initial inspection was static. Follow-up live catalog retrieval succeeded and sample renders were downloaded; see `IDENTIFICATION.md`, `production-model-catalog.json`, and `renders/README.md`. No app installation or headphone connection was performed.

## Headphone identification

The app has several discovery and connection paths. The following paths are visible in the bytecode; this is not an exhaustive specification for every supported model.

1. **Bluetooth Low Energy advertisements:** `PacketFilterType.SONY_AUDIO` uses manufacturer bytes `2d 01` (manufacturer ID `0x012D`) and a manufacturer-data prefix `04 00`. The scanner/parser validates packet headers and dispatches supported packet versions. For example, `mh.d` parses model ID, model color, group/output state, and transport information. Other parsers handle additional packet formats.
2. **Model catalog lookup:** `com.sony.songpal.mdr.util.w0.a(ModelId, byte)` passes the advertised model ID and model-number byte to `CloudModelInfoController.getModelName(byte, byte)`. The controller matches catalog `model_id` and `model_number` entries to obtain a model name.
3. **Connected device information:** Sony's Tandem protocol includes `DeviceInfoInquiredType.MODEL_NAME`, `FW_VERSION`, and `SERIES_AND_COLOR_INFO`. The connected `DeviceState` exposes model name and `ModelColor`; the header artwork reads these values directly.
4. **Classic Bluetooth control connection:** the app includes RFCOMM connection code (`ep0.c.a`) that opens a socket for a Sony service UUID. `lm0.i$a.a()` returns `96CC203E-5068-46ad-B32D-E316F5E069BA`. There are additional UUIDs and connection families, so this is not the only transport in the app.

The identification system therefore has richer information than the editable Bluetooth display name alone: manufacturer advertising data, model identifiers, color, and connected protocol responses.

## Animated product renders

**The animated header renders are downloaded APNG files; none were found bundled in these APKs.**

Verified playback chain:

```text
DeviceState → model name + ModelColor
  → CloudModelInfoController.getModelAnimeUrl(name, color)
  → catalog field sca_anime_image_url
  → BigHeaderModelImage.F(...)
  → DownloadedFileManager
  → local file
  → t9.a drawable
  → com.github.penfeizhou.animation.apng.decode decoder
```

`CloudModelInfoController` requests a `GetAllCloudModelInfos` GraphQL catalog under `HPC`, including `model_id`, `model_number`, `model_name`, `model_color_id`, `sca_image_image_url`, and `sca_anime_image_url`. It saves the catalog JSON and refresh timestamp locally. Model name and color are used to select artwork.

`BigHeaderModelImage` also supports an Android bundled-asset URI, but the package inventory found no bundled APNG render. If no animation URL or usable downloaded file is available, the header has a static-image fallback.

### Cache location and filenames

`com.sony.songpal.mdr.vim.m.a()` constructs the image directory from `Context.getFilesDir()` and `modelimage`:

```text
<Sound Connect private app data>/files/modelimage/
```

`lz.k.q(url)` hashes the URL with **SHA-1** and formats the digest as lowercase hexadecimal for the filename. An installed app's cached animation may therefore have a 40-character filename with no `.png` extension. APK extraction does not include this private runtime data. This inspection establishes the cache implementation, not whether a particular installed app has already downloaded a particular model's render.

## What is bundled

- 2,908 PNG-signature files across the supplied base and split APKs; none contained the APNG `acTL` animation marker. All archive entries were checked by signature, including files without a `.png` extension.
- Generic light/dark earbud and charging-case placeholder artwork, plus pairing illustrations. See `bundled-earbud-artwork.jpg` and the extracted PNGs in this directory.
- Lottie instructional animations, including head nodding, head turning, calibration, and multipoint pairing. Four examples were extracted here. These are instructional illustrations, not model-specific product turntables.
- Three party-feature MP4s in `res/raw/a_anime_sca_party_*.mp4`; these are not named as earbud product renders.
- No `.glb`, `.gltf`, `.fbx`, or `.obj` model files found in the supplied archives.

The bundled `assets/model_info_list_for_debug.json` contains development/example model data. Its sample URLs and model entries should not be treated as the production catalog or authoritative product-artwork URLs.

## Reusable evidence

`verified-code-references.json` records relevant class names, method signatures, literal strings, and actual decoded Dalvik invocation references from the six DEX files. Names such as `mh.d`, `t9.a`, and `lz.k` are the APK's obfuscated class names. Analysis did not modify the macOS app's source code.

Follow-up: production `sca_anime_image_url` values were successfully retrieved from Sony's live catalog using the application client identifier bundled in the native library. Ten original APNG animations and one static image were downloaded into `renders/`; each has a source URL recorded in `renders/index.json`. See `IDENTIFICATION.md` for the recovered read-only identity request/reply layouts and the proposed notch integration.
