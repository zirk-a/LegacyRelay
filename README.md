# LegacyRelay

LegacyRelay is an iOS browser with WebKit and Gecko support. It provides browser-session export and import for compatible applications and devices.

## Session archives

LegacyRelay exports encrypted '.mgsession' files. Each archive uses a file-specific username and password, independent of the website account credentials. Argon2id derives the encryption key, and XChaCha20-Poly1305 authenticates and encrypts the session payload through libsodium 1.0.20. A new random salt and nonce are used for each export.

Supported session transfers preserve portable cookies and their supported attributes. Import/export between Gecko and WebKit has been tested in both directions, including across different devices and application variants, with session persistence after restart. Portable cookie archives do not include full Gecko profiles, IndexedDB databases or service-worker storage. Websites may invalidate transferred sessions or require additional authentication.

## Build requirements

- macOS with Xcode and an iPhoneOS SDK (tested with Xcode 13.4.1 and iPhoneOS 15.5 SDK)
- Python 3 and Git
- libsodium 1.0.20 source archive (downloaded and SHA256-verified by the build scripts)
- Rust, Cargo and the `aarch64-apple-ios` target for sideload JIT dependencies
- A GeckoView development SDK with `DevelopedGeckoView.framework/Headers` and `DevelopedGeckoView.framework/Modules`
- Compatible Reynard/Gecko runtime dependencies

The GeckoView development SDK can be provided using `LEGACYRELAY_GECKO_SDK` or placed in `BuildSupport/GeckoSDK/`. Runtime binaries are separate from the development interface. The build scripts can reuse local compatible Gecko binaries and retrieve public upstream runtime components; a clean checkout may require additional compatible runtime files and headers. Gecko itself is not rebuilt by these scripts.

## Build

```bash
chmod +x Build.command BuildScripts/*.sh
./Build.command all
```

Individual variants:

```bash
./Build.command sideload
./Build.command trollstore
./Build.command webkit
```

Build outputs are written to `BuildProducts/`.

| Variant | Output | Engine |
| --- | --- | --- |
| Sideload | `LegacyRelay-Sideload.ipa` | Gecko and WebKit |
| TrollStore | `LegacyRelay-TrollStore.tipa` | Gecko and WebKit |
| WebKit-only | `LegacyRelay-WebKit.ipa` | WebKit |

All variants use the bundle identifier `com.zirka.legacyrelay`. Installing a variant with the same identifier replaces the previous variant rather than creating a separate app.

## Source structure

| Path | Component |
| --- | --- |
| `Sources/` | Application and sideload implementation |
| `Variants/TrollStore/` | TrollStore implementation |
| `WebKitOnly/` | WebKit-only application settings |
| `Security/` | Encrypted session format |
| `Resources/extensions/` | Gecko cookie-bridge extension |
| `Bridges/` | JIT and platform integration |
| `BuildScripts/` | Dependency preparation, compilation and packaging |
| `Configurations/` | Shared and variant build settings |
| `External/` | Upstream integration and runtime interfaces |

## License and attribution

The project integrates components from Reynard, Mozilla Gecko, User Agent Switcher, libsodium and idevice. See [CREDITS.md](CREDITS.md) and the included license files for attribution and applicable terms.
