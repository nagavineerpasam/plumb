#!/bin/bash
# Installs (or updates) Plumb in /Applications from the latest GitHub release.
#
#   curl -fsSL https://plumbapp.vercel.app/install.sh | bash
#
# What it does, and nothing more:
#   1. checks this Mac can run Plumb (Apple Silicon, macOS 14+)
#   2. downloads Plumb.dmg and its SHA-256 fingerprint from github.com/nagavineerpasam/plumb
#   3. refuses to continue unless the download matches the fingerprint
#   4. copies Plumb.app into /Applications (replacing an older Plumb) and opens it
# No sudo, no password, no change to macOS security settings, nothing outside /Applications/Plumb.app.
# Your notes and settings are left untouched.
#
# Downloaded with curl, the app isn't marked "downloaded from the internet", so macOS opens it
# without the "could not verify" dialog (Plumb isn't signed with a paid Apple Developer ID yet).
set -euo pipefail

RELEASE="https://github.com/nagavineerpasam/plumb/releases/latest/download"
APP="/Applications/Plumb.app"

step() { printf '\033[1m▸ %s\033[0m\n' "$*"; }
fail() { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

# Everything runs from main, called on the last line, so a half-downloaded script does nothing.
main() {
  [ "$(uname -s)" = "Darwin" ] || fail "Plumb is a Mac app."
  [ "$(uname -m)" = "arm64" ] || fail "Plumb needs a Mac with Apple Silicon (M1 or newer)."
  local version
  version="$(sw_vers -productVersion)"
  [ "${version%%.*}" -ge 14 ] || fail "Plumb needs macOS 14 or newer; this Mac has macOS $version."
  [ -w /Applications ] || fail "Can't write to /Applications. Run this from an administrator account."

  work="$(mktemp -d)"
  mount="$work/volume"
  trap 'hdiutil detach "$mount" -quiet 2>/dev/null || true; rm -rf "$work"' EXIT

  step "Downloading Plumb"
  curl -fL --progress-bar -o "$work/Plumb.dmg" "$RELEASE/Plumb.dmg"
  curl -fsSL -o "$work/Plumb.dmg.sha256" "$RELEASE/Plumb.dmg.sha256"

  step "Checking the download"
  (cd "$work" && shasum -a 256 -c Plumb.dmg.sha256 >/dev/null) \
    || fail "The download doesn't match its published fingerprint, so nothing was installed. Please try again."

  step "Installing into Applications"
  hdiutil attach "$work/Plumb.dmg" -nobrowse -readonly -mountpoint "$mount" -quiet
  if pgrep -xq Plumb; then
    osascript -e 'tell application id "io.github.nagavineerpasam.plumb" to quit' >/dev/null 2>&1 || true
    sleep 2
  fi
  # Keep the old copy until the new one is in place, so a failed copy never leaves you without Plumb.
  if [ -d "$APP" ]; then mv "$APP" "$work/previous.app"; fi
  if ! ditto "$mount/Plumb.app" "$APP"; then
    rm -rf "$APP"
    if [ -d "$work/previous.app" ]; then mv "$work/previous.app" "$APP"; fi
    fail "Couldn't copy Plumb into Applications."
  fi

  step "Opening Plumb"
  open "$APP"
  printf '\nPlumb is installed. The first launch downloads its writing model once (about 800 MB).\n'
}

main "$@"
