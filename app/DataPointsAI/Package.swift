// swift-tools-version: 6.2
import PackageDescription

// DataPointsAI is a SwiftUI macOS app built with SwiftPM instead of Xcode.
//
// SwiftPM only produces a bare executable — it has no notion of an .app bundle,
// an Info.plist, or an asset catalog. Scripts/build-app.sh wraps the binary
// produced here into build/DataPointsAI.app. See Scripts/README.md.
//
// The settings below mirror the build settings the old .xcodeproj carried, so
// the source compiles identically:
//   SWIFT_VERSION                  = 5.0  -> swiftLanguageMode(.v5)
//   SWIFT_DEFAULT_ACTOR_ISOLATION  = MainActor -> defaultIsolation(MainActor.self)
//   SWIFT_APPROACHABLE_CONCURRENCY = YES  -> the upcoming features listed below
//   SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES
let package = Package(
    name: "DataPointsAI",
    platforms: [.macOS("15.7")],
    targets: [
        .executableTarget(
            name: "DataPointsAI",
            path: "DataPointsAI",
            // Compiling an asset catalog needs actool, which ships only inside
            // Xcode. build-app.sh renders AppIcon to an .icns with iconutil
            // instead, so the catalog is not a build input here.
            exclude: ["Assets.xcassets"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .defaultIsolation(MainActor.self),
                // SWIFT_APPROACHABLE_CONCURRENCY expands to this feature set.
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferSendableFromCaptures"),
                .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
                .enableUpcomingFeature("DisableOutwardActorInference"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        )
    ]
)
