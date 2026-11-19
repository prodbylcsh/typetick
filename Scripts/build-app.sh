#!/bin/bash
# Builds Typetick.app from the Swift package (no Xcode project needed).
#   Scripts/build-app.sh            # release build into build/Typetick.app
#   Scripts/build-app.sh debug
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG" --product Typetick
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="build/Typetick.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Typetick" "$APP/Contents/MacOS/Typetick"
# SwiftPM resource bundles (the component library) live next to the binary.
for b in "$BIN"/*.bundle; do cp -R "$b" "$APP/Contents/Resources/"; done
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Typetick</string>
  <key>CFBundleDisplayName</key><string>Typetick</string>
  <key>CFBundleIdentifier</key><string>app.typetick.Typetick</string>
  <key>CFBundleExecutable</key><string>Typetick</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
