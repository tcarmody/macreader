#!/usr/bin/env bash
# Shared config and helpers for the DataPointsAI build scripts.
# Source from each script: `source "$(dirname "$0")/_lib.sh"`

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="DataPointsAI"
BUNDLE_ID="com.tcarmody.DataPointsAI"

# Layout
BUNDLE_ASSETS="$PROJECT_ROOT/BundleAssets"
ASSET_CATALOG="$PROJECT_ROOT/$APP_NAME/Assets.xcassets"
BUILD_DIR="$PROJECT_ROOT/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"

# Architectures to build. Override for a universal binary:
#   ARCHS="arm64 x86_64" ./Scripts/build-app.sh
ARCHS="${ARCHS:-arm64}"

# Set PREVIEWS=1 to compile the #Preview blocks. Requires the Xcode toolchain —
# see the note in select_toolchain below.
PREVIEWS="${PREVIEWS:-0}"

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(basename "$0")" "$*" >&2; }
warn() { printf '\033[1;33m[%s]\033[0m %s\n' "$(basename "$0")" "$*" >&2; }
die()  { printf '\033[1;31m[%s]\033[0m %s\n' "$(basename "$0")" "$*" >&2; exit 1; }

# Pick the Swift toolchain.
#
# Default is the standalone Command Line Tools, not Xcode. That is the whole
# point of this build: CLT ships swiftc, the macOS SDK, and SwiftPM, so the app
# builds on a machine with no Xcode.app at all. It does NOT ship
# libPreviewsMacros.dylib, which is why #Preview is behind -DPREVIEWS.
#
# Override explicitly if you want Xcode's toolchain:
#   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./Scripts/build-app.sh
SWIFT=""
select_toolchain() {
    [[ -n "$SWIFT" ]] && return

    if [[ -z "${DEVELOPER_DIR:-}" && -x /Library/Developer/CommandLineTools/usr/bin/swift ]]; then
        export DEVELOPER_DIR=/Library/Developer/CommandLineTools
    fi

    if [[ -n "${DEVELOPER_DIR:-}" && -x "$DEVELOPER_DIR/usr/bin/swift" ]]; then
        SWIFT="$DEVELOPER_DIR/usr/bin/swift"
    else
        SWIFT="$(command -v swift)" || die "No swift found. Install the Command Line Tools: xcode-select --install"
    fi

    local version
    if ! version="$("$SWIFT" --version 2>&1)"; then
        # The most common failure by far on a Mac with Xcode installed.
        if grep -q "license" <<<"$version"; then
            die "Toolchain at $SWIFT needs the Xcode license accepted.
  Either run: sudo xcodebuild -license accept
  Or use the Command Line Tools instead (no license prompt):
    xcode-select --install"
        fi
        die "swift is not usable:
$version"
    fi

    log "Toolchain: $(head -1 <<<"$version")"
    log "DEVELOPER_DIR=${DEVELOPER_DIR:-<default>}"

    if [[ "$PREVIEWS" == "1" && "${DEVELOPER_DIR:-}" == "/Library/Developer/CommandLineTools" ]]; then
        warn "PREVIEWS=1 with the Command Line Tools toolchain will fail —"
        warn "libPreviewsMacros.dylib ships only inside Xcode.app. Re-run with:"
        warn "  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer PREVIEWS=1 $0"
    fi
}

# Populate the global BUILD_FLAGS array for a single architecture.
#
# One arch per invocation on purpose. Passing --arch twice makes SwiftPM hand the
# build off to xcbuild, which lives in Xcode.app and is absent from the Command
# Line Tools. Building each slice separately and merging them with lipo produces
# the same universal binary using only CLT.
#
# Sets a global rather than echoing because macOS ships bash 3.2, which has no
# mapfile to read a multi-word result back into an array safely.
BUILD_FLAGS=()
swift_build_flags() {
    local arch="$1"
    BUILD_FLAGS=(-c release --arch "$arch")
    if [[ "$PREVIEWS" == "1" ]]; then
        BUILD_FLAGS+=(-Xswiftc -DPREVIEWS)
    fi
}

# Path to the linked executable for one architecture.
built_binary_path() {
    echo "$PROJECT_ROOT/.build/$1-apple-macosx/release/$APP_NAME"
}

# Resolve a codesigning identity to a SHA-1 hash, never a name — several certs
# can share a name and codesign refuses an ambiguous one. Falls back to ad-hoc
# ("-"), which is enough to launch locally but not on another Mac.
CODESIGN_IDENTITY_RESOLVED=""
resolve_signing_identity() {
    [[ -n "$CODESIGN_IDENTITY_RESOLVED" ]] && return

    local listing hash=""
    listing="$(security find-identity -v -p codesigning 2>/dev/null | grep -v REVOKED || true)"

    # Prefer Developer ID (distributable), then the configured default.
    hash="$(printf '%s\n' "$listing" | { grep "Developer ID Application" || true; } | head -1 | awk '{print $2}')"
    if [[ -z "$hash" ]]; then
        hash="$(printf '%s\n' "$listing" \
            | { grep "${CODESIGN_IDENTITY:-Apple Development}" || true; } | head -1 | awk '{print $2}')"
    fi

    if [[ -n "$hash" ]]; then
        CODESIGN_IDENTITY_RESOLVED="$hash"
        log "Signing identity: $(printf '%s\n' "$listing" | grep "$hash" | sed 's/^[^"]*"\([^"]*\)".*/\1/') ($hash)"
    else
        CODESIGN_IDENTITY_RESOLVED="-"
        warn "No signing identity found — using ad-hoc. Fine locally, will not run on another Mac."
    fi
}
