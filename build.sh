#!/bin/bash
# 构建 NiecheEmu.app（无需完整 Xcode，Command Line Tools 的 swiftc 就够）
set -e
cd "$(dirname "$0")"
APP="../NiecheEmu.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>NiecheEmu</string>
  <key>CFBundleDisplayName</key><string>尼彩 CBE 模拟器</string>
  <key>CFBundleIdentifier</key><string>local.nieche.cbeemu</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>NiecheEmu</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleIconFile</key><string>NiecheEmu</string>
</dict></plist>
PLIST

swiftc -O -parse-as-library \
  -target arm64-apple-macos13.0 \
  -sdk "$(xcrun --show-sdk-path)" \
  -framework SwiftUI -framework AppKit -framework AVFoundation \
  -o "$APP/Contents/MacOS/NiecheEmu" \
  NiecheEmu.swift Library.swift Upscale.swift Keypad.swift Sound.swift

cp icons/NiecheEmu.icns "$APP/Contents/Resources/"

# 把项目目录写进 app，运行时才知道去哪找 tools/engine.py
PROJ="$(cd .. && pwd)"
cat > "$APP/Contents/Resources/project_dir" <<EOF
$PROJ
EOF
echo "已构建 $APP"
