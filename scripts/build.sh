#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${SWIFTPM_DISABLE_SANDBOX:-0}" == "1" ]]; then
    swift build --build-system native --disable-sandbox -c release
else
    swift build --build-system native -c release
fi
APP="$PWD/dist/MouseFlip.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Assets/MouseFlip.icns "$APP/Contents/Resources/MouseFlip.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp .build/release/MouseFlip "$APP/Contents/MacOS/MouseFlip"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MouseFlip</string>
<key>CFBundleIdentifier</key><string>local.datalogik.MouseFlip</string>
<key>CFBundleIconFile</key><string>MouseFlip.icns</string>
<key>CFBundleName</key><string>MouseFlip</string>
<key>CFBundleDisplayName</key><string>MouseFlip</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.6</string>
<key>CFBundleVersion</key><string>7</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
