#!/bin/bash

set -e
cd "$(dirname "$0")"
./build.sh
APP="../NiecheEmu.app"
SRC="$(cd .. && pwd)"

ENG="$APP/Contents/Resources/pyengine"
rm -rf "$ENG"; mkdir -p "$ENG/tools"

cp -R "$SRC/emu" "$SRC/cbelib" "$ENG/"
cp "$SRC/tools/engine.py" "$ENG/tools/"

SITE=$(python3 -c 'import unicorn, os; print(os.path.dirname(os.path.dirname(unicorn.__file__)))')
cp -R "$SITE/unicorn" "$SITE/capstone" "$ENG/"
find "$ENG" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
find "$ENG" -name '*.a' -delete 2>/dev/null || true

rm -f "$APP/Contents/Resources/project_dir"
echo "Python 回落引擎已打包：$(du -sh "$ENG" | cut -f1)"
if [ -x "$APP/Contents/Resources/engine" ]; then
  echo "Rust 主引擎已打包：$(du -sh "$APP/Contents/Resources/engine" | cut -f1)"
else
  echo "警告：没有 Rust 主引擎，发布包会一直走 Python 回落"
fi

cd ..
rm -f NiecheEmu-macos.zip
ditto -c -k --sequesterRsrc --keepParent NiecheEmu.app NiecheEmu-macos.zip
echo "发布包：$(ls -lh NiecheEmu-macos.zip | awk '{print $5}')  NiecheEmu-macos.zip"
