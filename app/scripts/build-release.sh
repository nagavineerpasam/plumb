#!/bin/bash
# Builds Plumb.app (with its own Python and the signal engine inside) and Plumb.dmg.
# Usage: app/scripts/build-release.sh [version]     Output: dist/
set -euo pipefail

VERSION="${1:-0.1.0}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Plumb.app"
CACHE="$DIST/cache"
PYTHON_URL="https://github.com/astral-sh/python-build-standalone/releases/download/20260924/cpython-3.12.14%2B20260924-aarch64-apple-darwin-install_only.tar.gz"

echo "▸ Building the app (release)"
swift build -c release --package-path "$ROOT/app" --arch arm64

echo "▸ Assembling Plumb.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$CACHE"
BIN="$(swift build -c release --package-path "$ROOT/app" --arch arm64 --show-bin-path)"
cp "$BIN/Plumb" "$APP/Contents/MacOS/Plumb"
cp "$ROOT/app/Sources/Plumb/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Plumb</string>
  <key>CFBundleDisplayName</key><string>Plumb</string>
  <key>CFBundleIdentifier</key><string>io.github.nagavineerpasam.plumb</string>
  <key>CFBundleExecutable</key><string>Plumb</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Plumb listens only while you click Speak, to type what you say into your note. Everything stays on your Mac.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Plumb turns your speech into text on your Mac, without sending it anywhere.</string>
</dict>
</plist>
PLIST

echo "▸ Adding a self-contained Python with the signal engine"
[ -f "$CACHE/python.tar.gz" ] || curl -fL --retry 3 -o "$CACHE/python.tar.gz" "$PYTHON_URL"
tar -xzf "$CACHE/python.tar.gz" -C "$APP/Contents/Resources"   # creates Resources/python
PY="$APP/Contents/Resources/python/bin/python3"
"$PY" -m pip install --quiet --no-cache-dir --disable-pip-version-check "$ROOT/engine"
# Trim what the app never uses at runtime.
SITE="$APP/Contents/Resources/python/lib/python3.12"
rm -rf "$SITE/test" "$SITE/idlelib" "$SITE/tkinter" "$SITE/ensurepip" "$SITE/lib2to3" "$SITE/pydoc_data"
PKGS="$SITE/site-packages"
# Tested removable: none of these are imported at runtime. (torch/bin, torchgen and sympy are
# needed and must stay.)
rm -rf "$PKGS/torch/include" "$PKGS/torch/share" "$PKGS/pip" "$PKGS"/pip-*.dist-info \
       "$PKGS/setuptools" "$PKGS"/setuptools-*.dist-info "$PKGS/_distutils_hack" "$PKGS/distutils-precedence.pth" \
       "$PKGS/pygments" "$PKGS"/pygments-*.dist-info "$PKGS/hf_xet" "$PKGS"/hf_xet-*.dist-info \
       "$PKGS/networkx" "$PKGS"/networkx-*.dist-info
find "$APP/Contents/Resources/python" -name "__pycache__" -type d -prune -exec rm -rf {} +
"$PY" -c "import writing_signals, laya, torch; print('  engine OK, torch', torch.__version__)"

echo "▸ Signing (ad hoc; Apple Silicon requires a signature to run)"
codesign --force --deep --sign - "$APP"
codesign --verify --deep "$APP"

echo "▸ Making the disk image"
STAGE="$DIST/dmg"
rm -rf "$STAGE" && mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/Plumb.dmg"   # fixed name: the README links to releases/latest/download/Plumb.dmg
rm -f "$DMG"
hdiutil create -quiet -volname "Plumb" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "✓ $(du -sh "$APP" | cut -f1) app, $(du -sh "$DMG" | cut -f1) disk image: $DMG"
