# LegacyRelay 0.3

LegacyRelay is an iOS browser for web authentication and session management. It supports built-in websites and custom URLs through WebKit or Gecko integration from [Reynard Browser](https://github.com/minh-ton/reynard-browser). Browser sessions can be exported for use with compatible clients and tools.

## Browser engines

WebKit provides session-cookie export and import for custom websites. Gecko provides separate profiles, Firefox add-on integration, session-cookie export (`.mgsession`) and full-profile backup and restore. Other applications can consume exported sessions by implementing support for the corresponding format. Session exports contain authentication cookies and should be handled as sensitive files.

## Build requirements

- macOS and Xcode with an iPhoneOS SDK (the project has been built using Xcode 13.4.1 and iPhoneOS 15.5 SDK).
- Python 3 and Git.
- Rust, Cargo and an `aarch64-apple-ios` target for the standard sideload JIT dependencies.
- A **matching GeckoView development SDK**, containing `DevelopedGeckoView.framework/Headers` and `DevelopedGeckoView.framework/Modules`.
- Internet access on the first build to retrieve Reynard 0.16.0 runtime packages, the Firefox add-on and the sideload dependencies.

The GeckoView development SDK is separate from the Gecko runtime packaged in Reynard's public IPA/TIPA. It can be supplied using `LEGACYRELAY_GECKO_SDK` or placed in `BuildSupport/GeckoSDK/` as the `Headers/` and `Modules/` directories. Without this development interface, Swift cannot compile against GeckoView.

## Build commands

From the project root:

```bash
chmod +x Build.command BuildScripts/*.sh
./Build.command both
```

To compile an individual variant:

```bash
./Build.command sideload
./Build.command trollstore
```

Packages are written to `BuildProducts/`:

| Variant | Output | Installation |
| --- | --- | --- |
| Sideload | `LegacyRelay-Sideload.ipa` | Sideload signing and JIT configuration |
| TrollStore | `LegacyRelay-TrollStore.tipa` | TrollStore installation and JIT helper |

Both variants use the application Bundle ID `com.legacyrelay.app` and the display name `LegacyRelay`. They are alternative packages for the same application and cannot be installed side by side. `LEGACYRELAY_BUNDLE_ID` overrides the application ID for packaging both variants; the sideload helper ID is derived from the application ID.

The build scripts reuse compatible local Gecko binaries when they are already present. They can also attempt to obtain the public Reynard 0.16.0 runtime, but **the public release may not contain every binary needed to compile and package LegacyRelay**. A clean checkout is therefore not guaranteed to build without additional compatible Gecko runtime files and the matching development SDK. Gecko itself is not compiled by these scripts. The sideload dependency script builds `jkcoxson/idevice` from its upstream default branch; the fetched revision can vary between builds.

## Project structure

| Path | Contents |
| --- | --- |
| `Sources/` | Common application and sideload implementation |
| `Variants/TrollStore/` | TrollStore-specific application implementation |
| `Bridges/` | Gecko/JIT bridge sources |
| `Configurations/` | Shared and variant-specific Xcode settings |
| `BuildScripts/` | Dependency preparation, compilation, packaging and validation |
| `External/Reynard/` | Upstream Reynard integration sources |
| `LICENSE`, `CREDITS.md` | Licensing and third-party attribution |

## Licenses and third-party components

LegacyRelay incorporates code from Reynard and components associated with Gecko, User Agent Switcher and `idevice`. Attribution and upstream project links are in [CREDITS.md](CREDITS.md); the project license is in `LICENSE`; third-party license terms must be checked in each upstream distribution.
