#!/usr/bin/env bash
# Code-sign DataPointsAI.app.
#
# The bundle has no nested frameworks, dylibs, or helper tools — SwiftPM links a
# single executable against system frameworks only — so this is a two-step sign
# rather than the inside-out walk a bundle with embedded binaries would need.
#
# --options runtime is what ENABLE_HARDENED_RUNTIME=YES used to do in the
# .xcodeproj; it is a codesign flag, not an entitlement.

source "$(dirname "$0")/_lib.sh"

[[ -d "$APP_BUNDLE" ]] || die "No bundle at $APP_BUNDLE — run Scripts/build-app.sh first"

# The entitlements file is an empty dict on purpose, mirroring the old
# .xcodeproj: ENABLE_APP_SANDBOX=NO, every RUNTIME_EXCEPTION_*=NO, and
# AUTOMATION_APPLE_EVENTS=NO. Unsandboxed, the app already has what it needs —
# outbound network, the login keychain, notifications, Spotlight, and spawning
# the Python backend as a subprocess.
#
# Keep it free of XML comments. codesign hands entitlements to AMFI's own plist
# parser, which is stricter than plutil and fails with "AMFIUnserializeXML:
# syntax error" on a comment that every other plist tool accepts.
ENTITLEMENTS="$BUNDLE_ASSETS/$APP_NAME.entitlements"
[[ -f "$ENTITLEMENTS" ]] || die "Missing $ENTITLEMENTS"

resolve_signing_identity

SIGN_OPTS=(--force --options runtime --timestamp --sign "$CODESIGN_IDENTITY_RESOLVED")
if [[ "$CODESIGN_IDENTITY_RESOLVED" == "-" ]]; then
    # A secure timestamp needs Apple's TSA over the network, and ad-hoc
    # signatures can never be notarized anyway — skip it and stay offline.
    SIGN_OPTS=(--force --options runtime --sign -)
fi

log "Signing the main executable"
codesign "${SIGN_OPTS[@]}" --entitlements "$ENTITLEMENTS" "$APP_MACOS/$APP_NAME"

log "Sealing the bundle"
codesign "${SIGN_OPTS[@]}" --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"

log "Verifying"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

# Gatekeeper assessment only passes for a Developer ID signature; an ad-hoc
# build launches fine on this Mac but is expected to fail here.
if spctl --assess --type execute "$APP_BUNDLE" 2>/dev/null; then
    log "Gatekeeper: accepted"
else
    warn "Gatekeeper: rejected (expected for an ad-hoc or Apple Development signature)"
fi

log "Done. Launch with Scripts/run-app.sh"
