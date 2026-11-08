#!/bin/zsh
# Builds "GMMK Lights.app" into ./build. Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP="build/GMMK Lights.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/GMMKBar "$APP/Contents/MacOS/GMMKBar"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>GMMK Lights</string>
  <key>CFBundleDisplayName</key><string>GMMK Lights</string>
  <key>CFBundleIdentifier</key><string>local.gmmk.lights</string>
  <key>CFBundleExecutable</key><string>GMMKBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Personal build</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built: $PWD/$APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x GMMKBar 2>/dev/null || true
  rm -rf "/Applications/GMMK Lights.app"
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/GMMK Lights.app"
fi
