#!/bin/bash

set -e
cd "$(dirname "$0")"
./build.sh
APP="../NiecheEmu.app"

if [ ! -x "$APP/Contents/Resources/engine" ]; then
  echo "!! Resources/engine 不在——先在 emu-core-rs 里 cargo build --release"
  exit 1
fi
echo "Rust 引擎：$(du -h "$APP/Contents/Resources/engine" | cut -f1)"

rm -f "$APP/Contents/Resources/project_dir"
rm -rf "$APP/Contents/Resources/pyengine"

codesign --force --sign - "$APP/Contents/Resources/engine" >/dev/null 2>&1
codesign --force --sign - "$APP"
codesign --verify --strict --deep "$APP" && echo "签名校验通过"

cd ..
rm -f NiecheEmu-macos.zip
ditto -c -k --sequesterRsrc --keepParent NiecheEmu.app NiecheEmu-macos.zip
echo "发布包：$(ls -lh NiecheEmu-macos.zip | awk '{print $5}')  NiecheEmu-macos.zip"
