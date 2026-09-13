#!/bin/bash

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

DEV=""
if [ -f DevPythonEngine.swift ]; then
  DEV="-D DEV_PY DevPythonEngine.swift"
  echo "带上 Python 引擎（本地开发验证用）"
fi

SDKS="$(xcrun --show-sdk-path 2>/dev/null)"
for d in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX[0-9]*.sdk 2>/dev/null | sort -rV); do
  SDKS="$SDKS $d"
done
BUILT=""
for SDK in $SDKS; do
  [ -d "$SDK" ] || continue
  if swiftc -O -parse-as-library \
       -target arm64-apple-macos13.0 \
       -sdk "$SDK" \
       -framework SwiftUI -framework AppKit -framework AVFoundation \
       -o "$APP/Contents/MacOS/NiecheEmu" \
       $DEV \
       NiecheEmu.swift Library.swift Upscale.swift Keypad.swift Sound.swift 2>/tmp/nieche-swiftc.log; then
    BUILT="$SDK"
    break
  fi
done
if [ -z "$BUILT" ]; then
  echo "!! 所有可用 SDK 都编不过，最后一次的错误："
  tail -20 /tmp/nieche-swiftc.log
  exit 1
fi
echo "SDK：$(basename "$BUILT")"

cp icons/NiecheEmu.icns "$APP/Contents/Resources/"

ENGINE="${CARGO_TARGET_DIR:-$HOME/.cache/nieche-rust}/release/engine"
if [ -x "$ENGINE" ]; then
  cp "$ENGINE" "$APP/Contents/Resources/engine"
  echo "已打包 Rust 引擎"
else
  echo "没找到 Rust 引擎（$ENGINE），app 会回落到 Python 引擎"
fi

sign_app() {
  [ -x "$APP/Contents/Resources/engine" ] &&     codesign --force --sign - "$APP/Contents/Resources/engine" >/dev/null 2>&1
  codesign --force --sign - "$APP" >/dev/null 2>&1
  codesign --verify --strict --deep "$APP" 2>&1 | sed 's/^/   /'
}

PROJ="$(cd .. && pwd)"
cat > "$APP/Contents/Resources/project_dir" <<EOF
$PROJ
EOF
echo "已构建 $APP"

sign_app
echo "已签名（ad-hoc）"
