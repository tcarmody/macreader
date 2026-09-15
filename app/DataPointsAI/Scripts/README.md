# Building DataPointsAI without Xcode

The macOS app is a SwiftPM package (`Package.swift`) plus three shell scripts
that wrap the compiled binary into a `.app` bundle. There is no `.xcodeproj`.

The build runs on the standalone **Command Line Tools** — `xcode-select
--install` — so Xcode.app does not need to be installed at all.

```bash
cd app/DataPointsAI
./Scripts/build-app.sh     # compile + assemble build/DataPointsAI.app
./Scripts/sign-app.sh      # codesign + verify
./Scripts/run-app.sh       # launch with stdout/stderr on the terminal
```

Or from the repo root: `make app` (all three), `make app-build`, `make app-run`.

## Why scripts and not just `swift build`

SwiftPM only produces a bare Mach-O executable. It has no concept of an `.app`
bundle, an `Info.plist`, or an asset catalog — all three used to be synthesized
by Xcode from build settings. The scripts reproduce them:

| Xcode did this | Now |
| --- | --- |
| `GENERATE_INFOPLIST_FILE = YES` | `BundleAssets/Info.plist`, copied verbatim |
| Compiled `Assets.xcassets` with `actool` | `iconutil` renders `AppIcon.icns` from the same catalog |
| Signed with `ENABLE_HARDENED_RUNTIME` | `sign-app.sh`, `codesign --options runtime` |
| Wrote `DataPointsAI.app` to DerivedData | `build/DataPointsAI.app` |

`actool` ships only inside Xcode.app, which is why the icon goes through
`iconutil` instead. That is fine here: the catalog's only real content is the
AppIcon set — `AccentColor` is an empty placeholder, and nothing in the Swift
sources references generated asset symbols. `build-app.sh` reads the size/scale
mapping out of `Assets.xcassets/AppIcon.appiconset/Contents.json`, so the
catalog stays the single source of truth for icons.

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
Swift 6.2. Verified against 6.2.4.

## `#Preview` and the `PREVIEWS` flag

The 21 `#Preview` blocks are wrapped in `#if PREVIEWS` and **compiled out by
default**. They expand via `libPreviewsMacros.dylib`, which ships inside
Xcode.app and not with the Command Line Tools; leaving them unguarded makes the
build fail on a machine without Xcode.

To compile them you need Xcode's toolchain — the plugin cannot be cross-loaded
into the CLT compiler, which fails with an ABI symbol mismatch:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer PREVIEWS=1 ./Scripts/build-app.sh
```

Previews only render inside Xcode anyway; open `Package.swift` directly (Xcode
opens a package as a project) and set `-DPREVIEWS` in the scheme's Swift flags.

## Options

Every script reads these from the environment:

| Variable | Default | Effect |
| --- | --- | --- |
| `ARCHS` | `arm64` | `ARCHS="arm64 x86_64"` builds a universal binary |

`build-app.sh` compiles one architecture at a time and merges the slices with
`lipo`. Passing `--arch` twice in a single `swift build` would hand the job to
`xcbuild`, which lives in Xcode.app and is missing from the Command Line Tools;
per-slice plus `lipo` gets the same universal binary with CLT alone.

| `PREVIEWS` | `0` | `1` compiles the `#Preview` blocks (needs Xcode's toolchain) |
| `DEVELOPER_DIR` | Command Line Tools | Point at another toolchain |
| `CODESIGN_IDENTITY` | `Apple Development` | Signing identity to prefer |

`sign-app.sh` resolves the identity to a SHA-1 hash rather than a name, because
several certificates can share a name and `codesign` refuses an ambiguous one.
It prefers a Developer ID Application cert if you have one, falls back to
`CODESIGN_IDENTITY`, and finally to ad-hoc (`-`). An ad-hoc or Apple Development
signature launches fine on this Mac but will not pass Gatekeeper elsewhere —
`sign-app.sh` says so rather than failing.

## Gotchas worth knowing

- **Entitlements must contain no XML comments.** `codesign` passes the file to
  AMFI's own plist parser, which is stricter than `plutil` and dies with
  `AMFIUnserializeXML: syntax error` on a comment every other plist tool
  accepts. `BundleAssets/DataPointsAI.entitlements` is an empty `<dict/>` on
  purpose — see the note in `sign-app.sh` for what it stands in for.
- **`Info.plist` needs `NSPrincipalClass = NSApplication`.** Without it the
  bundle launches as a faceless tool: no menu bar, no Dock tile, no windows.
- **If `swift` complains about the Xcode license**, you are on Xcode's
  toolchain, not the Command Line Tools. Either `sudo xcodebuild -license
  accept` or let the scripts default back to CLT.
