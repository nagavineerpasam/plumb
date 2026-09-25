#!/bin/bash
# Installs (or updates) Plumb in /Applications from the latest GitHub release.
#
#   curl -fsSL https://plumbapp.vercel.app/install.sh | bash
#
# Downloaded with curl, the app isn't marked "downloaded from the internet", so macOS opens it
# without the "could not verify" dialog (Plumb isn't signed with a paid Apple Developer ID yet).
# Your notes and settings are left untouched.
set -euo pipefail

DMG_URL="https://github.com/nagavineerpasam/plumb/releases/latest/download/Plumb.dmg"
APP="/Applications/Plumb.app"

step() { printf '\033[1m▸ %s\033[0m\n' "$*"; }
fail() { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Plumb is a Mac app."
[ "$(uname -m)" = "arm64" ] || fail "Plumb needs a Mac with Apple Silicon (M1 or newer)."
version="$(sw_vers -productVersion)"
[ "${version%%.*}" -ge 14 ] || fail "Plumb needs macOS 14 or newer; this Mac has macOS $version."
[ -w /Applications ] || fail "Can't write to /Applications. Run this from an administrator account."

work="$(mktemp -d)"
mount="$work/volume"
cleanup() {
  hdiutil detach "$mount" -quiet 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

step "Downloading Plumb"
curl -fL --progress-bar -o "$work/Plumb.dmg" "$DMG_URL"

step "Installing into Applications"
hdiutil attach "$work/Plumb.dmg" -nobrowse -readonly -mountpoint "$mount" -quiet
if pgrep -xq Plumb; then
  osascript -e 'tell application id "io.github.nagavineerpasam.plumb" to quit' >/dev/null 2>&1 || true
  sleep 2
fi
# Keep the old copy until the new one is in place, so a failed copy never leaves you without Plumb.
[ -d "$APP" ] && mv "$APP" "$work/previous.app"
if ! ditto "$mount/Plumb.app" "$APP"; then
  rm -rf "$APP"
  [ -d "$work/previous.app" ] && mv "$work/previous.app" "$APP"
  fail "Couldn't copy Plumb into Applications."
fi

step "Opening Plumb"
open "$APP"
printf '\nPlumb is installed. The first launch downloads its writing model once (about 800 MB).\n'
