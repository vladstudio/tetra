#!/bin/bash
set -e
cd "$(dirname "$0")"

# Build
swift build -c release

# Generate .icns from app-icon.png
ICONSET=/tmp/TetraIcon.iconset
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 16 16     icons/app-icon.png --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32     icons/app-icon.png --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32     icons/app-icon.png --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64     icons/app-icon.png --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128   icons/app-icon.png --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256   icons/app-icon.png --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   icons/app-icon.png --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512   icons/app-icon.png --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   icons/app-icon.png --out "$ICONSET/icon_512x512.png"    >/dev/null
sips -z 1024 1024 icons/app-icon.png --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o /tmp/AppIcon.icns
rm -rf "$ICONSET"

# Assemble .app bundle
APP=/tmp/Tetra.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/"
cp .build/release/tetra "$APP/Contents/MacOS/"
cp -r .build/release/tetra_tetra.bundle "$APP/Contents/Resources/" 2>/dev/null || true
cp /tmp/AppIcon.icns "$APP/Contents/Resources/"

# Install
pkill -x Tetra 2>/dev/null || true
sleep 0.5
rm -rf /Applications/Tetra.app
mv "$APP" /Applications/
touch /Applications/Tetra.app
open /Applications/Tetra.app
echo "==> Installed Tetra.app"
