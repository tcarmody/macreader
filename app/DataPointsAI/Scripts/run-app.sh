#!/usr/bin/env bash
# Launch the built app and stream its stdout/stderr to this terminal.
#
# `open` would hand the process to launchd and swallow its output, which is the
# opposite of what you want while developing. Running the executable directly
# keeps print()/NSLog visible. macOS is happy to do this as long as the binary
# is invoked from inside a well-formed .app bundle, which it is.

source "$(dirname "$0")/_lib.sh"

[[ -x "$APP_MACOS/$APP_NAME" ]] || die "No built app — run Scripts/build-app.sh first"

log "Launching $APP_NAME (Ctrl-C to quit)"
exec "$APP_MACOS/$APP_NAME" "$@"
