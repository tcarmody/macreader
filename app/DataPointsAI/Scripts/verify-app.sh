#!/usr/bin/env bash
# Verify the release bundle against the active macOS SDK and its signature.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

[[ -d "$APP_BUNDLE" ]] || die "No bundle at $APP_BUNDLE — run make app-build first"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
log "Active macOS SDK: $SDK_VERSION"
[[ "${SDK_VERSION%%.*}" -ge 27 ]] || die "SDK 27 or newer is required (found $SDK_VERSION)"

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1 | grep -E 'Identifier=|TeamIdentifier=|Runtime Version=' >&2
plutil -p "$APP_CONTENTS/Info.plist" | grep -E 'CFBundleIdentifier|LSMinimumSystemVersion' >&2
log "Signed SDK 27 verification passed"
