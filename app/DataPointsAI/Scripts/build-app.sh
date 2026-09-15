#!/usr/bin/env bash
# Compile the Swift executable with SwiftPM and assemble DataPointsAI.app.
#
# SwiftPM produces a bare Mach-O executable and nothing else — it has no concept
# of an .app bundle, an Info.plist, or an asset catalog. So we build the bundle
# by hand:
#
#   build/DataPointsAI.app/
#     Contents/
#       Info.plist          <- BundleAssets/Info.plist, copied verbatim
#       MacOS/DataPointsAI  <- the SwiftPM binary
#       Resources/
#         AppIcon.icns      <- rendered from Assets.xcassets by iconutil
#
# The bundle is unsigned when this finishes. Run sign-app.sh next.

source "$(dirname "$0")/_lib.sh"

select_toolchain

# ---------------------------------------------------------------------------
# Compile
# ---------------------------------------------------------------------------
SLICES=()
for arch in $ARCHS; do
    swift_build_flags "$arch"   # sets BUILD_FLAGS
    log "Building $APP_NAME (release, $arch)"
    ( cd "$PROJECT_ROOT" && "$SWIFT" build "${BUILD_FLAGS[@]}" )

    slice="$(built_binary_path "$arch")"
    [[ -x "$slice" ]] || die "swift build did not produce $slice"
    SLICES+=("$slice")
done

# ---------------------------------------------------------------------------
# Assemble the bundle
# ---------------------------------------------------------------------------
log "Assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

if (( ${#SLICES[@]} > 1 )); then
    log "Merging ${#SLICES[@]} architecture slices with lipo"
    lipo -create -output "$APP_MACOS/$APP_NAME" "${SLICES[@]}"
else
    cp "${SLICES[0]}" "$APP_MACOS/$APP_NAME"
fi

cp "$BUNDLE_ASSETS/Info.plist" "$APP_CONTENTS/Info.plist"
plutil -lint "$APP_CONTENTS/Info.plist" >/dev/null || die "BundleAssets/Info.plist is not a valid plist"

# ---------------------------------------------------------------------------
# App icon
# ---------------------------------------------------------------------------
# Compiling Assets.xcassets would need actool, which ships only inside Xcode.
# The catalog's only real content is the AppIcon set (AccentColor is an empty
# placeholder and nothing in the Swift sources references generated asset
# symbols), so iconutil on a derived .iconset reproduces it exactly.
#
# The mapping is read out of the catalog's Contents.json rather than hardcoded,
# so adding or re-rendering an icon size stays a one-file change.
build_icns() {
    local contents="$ASSET_CATALOG/AppIcon.appiconset/Contents.json"
    if [[ ! -f "$contents" ]]; then
        warn "No AppIcon set at $contents — bundle will use the generic app icon"
        return
    fi

    local iconset
    iconset="$(mktemp -d)/$APP_NAME.iconset"
    mkdir -p "$iconset"

    local i=0 idiom size scale filename edge suffix
    while idiom="$(plutil -extract "images.$i.idiom" raw -o - "$contents" 2>/dev/null)"; do
        i=$((i + 1))
        # Skip the iOS 1024 entry: iconutil rejects unknown iconset members.
        [[ "$idiom" == "mac" ]] || continue

        filename="$(plutil -extract "images.$((i - 1)).filename" raw -o - "$contents" 2>/dev/null)" || continue
        size="$(plutil -extract "images.$((i - 1)).size" raw -o - "$contents")"
        scale="$(plutil -extract "images.$((i - 1)).scale" raw -o - "$contents")"

        # "16x16" -> 16 ; iconset names use the POINT size with an @2x suffix.
        edge="${size%%x*}"
        suffix=""
        [[ "$scale" == "2x" ]] && suffix="@2x"

        cp "$ASSET_CATALOG/AppIcon.appiconset/$filename" \
           "$iconset/icon_${edge}x${edge}${suffix}.png"
    done

    local n
    n="$(find "$iconset" -name '*.png' | wc -l | tr -d ' ')"
    if (( n == 0 )); then
        warn "AppIcon set contained no mac images — skipping icon"
        return
    fi

    log "Rendering AppIcon.icns from $n images"
    iconutil --convert icns --output "$APP_RESOURCES/AppIcon.icns" "$iconset"
    rm -rf "$(dirname "$iconset")"
}
build_icns

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
# Touch the bundle so Finder and LaunchServices notice the new Info.plist
# instead of serving a stale cached icon/version for the same path.
touch "$APP_BUNDLE"

log "Built $(du -sh "$APP_BUNDLE" | cut -f1) bundle:"
find "$APP_CONTENTS" -maxdepth 2 -mindepth 1 | sed "s|$APP_BUNDLE|  DataPointsAI.app|" >&2
log "Architectures: $(lipo -archs "$APP_MACOS/$APP_NAME" 2>/dev/null || echo unknown)"
log "Unsigned so far — run Scripts/sign-app.sh next."
