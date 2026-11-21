# Building DataPointsAI without Xcode

The macOS app is a SwiftPM package (`Package.swift`). There is no
`.xcodeproj`. The `.app` bundle is assembled by `dpcommon-macapp`, the build
tool from the shared [dpcommon](https://github.com/tcarmody/datapoints-common)
package, which Composer's Mac app uses too. Its settings for this app are the
`[tool.dpcommon.macapp]` table in the repo's `pyproject.toml`.

The build runs on the standalone **Command Line Tools** (`xcode-select
--install`), so Xcode.app does not need to be installed at all.

From the repo root:

```bash
make app          # compile, assemble and sign build/DataPointsAI.app
make app-run      # launch with stdout/stderr on the terminal
make app-verify   # check the signature and the SDK version
```

`make app-build` and `make app-sign` run the two halves separately. Each is
`uv run dpcommon-macapp <command>`; run `uv run dpcommon-macapp --help` for
every flag.

## Why a build tool and not just `swift build`

SwiftPM only produces a bare Mach-O executable. It has no concept of an `.app`
bundle, an `Info.plist`, or an asset catalog, all three of which Xcode used to
synthesize from build settings. `dpcommon-macapp` reproduces them:

| Xcode did this | Now |
| --- | --- |
| `GENERATE_INFOPLIST_FILE = YES` | `BundleAssets/Info.plist`, copied as is |
| Compiled `Assets.xcassets` with `actool` | `iconutil` renders `AppIcon.icns` from the same catalog |
| Signed with `ENABLE_HARDENED_RUNTIME` | `codesign --options runtime` |
| Wrote `DataPointsAI.app` to DerivedData | `build/DataPointsAI.app` |

The icon goes through `iconutil` (`icon.method = "iconutil"`) because the
catalog's only real content is the AppIcon set: `AccentColor` is an empty
placeholder, and nothing in the Swift sources references generated asset
symbols. The size/scale mapping is read from
`Assets.xcassets/AppIcon.appiconset/Contents.json`, so the catalog stays the
single source of truth for icons.

## Build settings

`Package.swift` mirrors what the `.xcodeproj` carried, so the sources compile
identically:

| Old build setting | `Package.swift` |
| --- | --- |
| `SWIFT_VERSION = 5.0` | `.swiftLanguageMode(.v5)` |
| `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` | `.defaultIsolation(MainActor.self)` |
| `SWIFT_APPROACHABLE_CONCURRENCY = YES` | the five upcoming features it expands to |
| `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY` | `.enableUpcomingFeature("MemberImportVisibility")` |
| `MACOSX_DEPLOYMENT_TARGET = 15.7` | `platforms: [.macOS("15.7")]` |

`.defaultIsolation` needs swift-tools-version 6.2, so the toolchain floor is
Swift 6.2. Builds and runs on 6.4.2, whose swift-build backend writes to
`.build/out/Products/Release`; the tool asks SwiftPM for the output path with
`--show-bin-path` rather than assuming one.

## `#Preview` and `--previews`

The 21 `#Preview` blocks are wrapped in `#if PREVIEWS` and **compiled out by
default**. They expand via `libPreviewsMacros.dylib`, which ships inside
Xcode.app and not with the Command Line Tools; leaving them unguarded makes the
build fail on a machine without Xcode.

To compile them you need Xcode's toolchain; the plugin cannot be cross-loaded
into the CLT compiler, which fails with an ABI symbol mismatch:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer uv run dpcommon-macapp build --previews
```

Previews only render inside Xcode anyway; open `Package.swift` directly (Xcode
opens a package as a project) and set `-DPREVIEWS` in the scheme's Swift flags.

## Options

| Flag / variable | Default | Effect |
| --- | --- | --- |
| `--arch ARCH` (repeatable), `--universal`, `ARCHS` | `arm64` | `--universal` builds arm64 + x86_64 |
| `--previews` | off | compiles the `#Preview` blocks (needs Xcode's toolchain) |
| `--debug` | release | debug configuration |
| `DEVELOPER_DIR` | Command Line Tools | point at another toolchain |
| `--sign`, `CODESIGN_IDENTITY` | auto | `-` for ad-hoc, a SHA-1 hash, or part of an identity's name |

Universal builds compile one architecture at a time and merge the slices with
`lipo`. Passing `--arch` twice in a single `swift build` would hand the job to
`xcbuild`, which lives in Xcode.app and is missing from the Command Line Tools.

Signing identities are resolved to a SHA-1 hash rather than a name, because
several certificates can share a name and `codesign` refuses an ambiguous one.
With no identity given, the tool prefers a Developer ID Application cert, then
Apple Development, and finally ad-hoc (`-`). An ad-hoc or Apple Development
signature launches fine on this Mac but will not pass Gatekeeper elsewhere; the
tool says so rather than failing.

## Gotchas worth knowing

- **Entitlements must contain no XML comments.** `codesign` passes the file to
  AMFI's own plist parser, which is stricter than `plutil` and dies with
  `AMFIUnserializeXML: syntax error` on a comment every other plist tool
  accepts. `BundleAssets/DataPointsAI.entitlements` is an empty `<dict/>` on
  purpose: the app is unsandboxed (`ENABLE_APP_SANDBOX=NO`, every
  `RUNTIME_EXCEPTION_*=NO` in the old project), which already gives it outbound
  network, the login keychain, notifications, Spotlight, and spawning the
  Python backend from `.venv` as a subprocess.
- **`Info.plist` needs `NSPrincipalClass = NSApplication`.** Without it the
  bundle launches as a faceless tool: no menu bar, no Dock tile, no windows.
- **If `swift` complains about the Xcode license**, you are on Xcode's
  toolchain, not the Command Line Tools. Either `sudo xcodebuild -license
  accept` or unset `DEVELOPER_DIR` so the tool defaults back to CLT.
