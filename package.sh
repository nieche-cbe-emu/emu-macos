#!/bin/bash
# 打一个自带引擎的发布包：用户下载解压即可运行，
# 不需要 clone 仓库，也不需要 pip 装 unicorn / capstone。
set -e
cd "$(dirname "$0")"
./build.sh
APP="../NiecheEmu.app"
SRC="$(cd .. && pwd)"
ENG="$APP/Contents/Resources/engine"
rm -rf "$ENG"; mkdir -p "$ENG/tools"

cp -R "$SRC/emu" "$SRC/cbelib" "$ENG/"
cp "$SRC/tools/engine.py" "$ENG/tools/"

# unicorn 和 capstone 都是纯 Python + ctypes，连同各自的 dylib 一起搬进来，
# 系统自带的 python3 就能跑。
SITE=$(python3 -c 'import unicorn, os; print(os.path.dirname(os.path.dirname(unicorn.__file__)))')
cp -R "$SITE/unicorn" "$SITE/capstone" "$ENG/"
find "$ENG" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
find "$ENG" -name '*.a' -delete 2>/dev/null || true

rm -f "$APP/Contents/Resources/project_dir"
echo "engine 已打包：$(du -sh "$ENG" | cut -f1)"

cd ..
rm -f NiecheEmu-macos.zip
ditto -c -k --sequesterRsrc --keepParent NiecheEmu.app NiecheEmu-macos.zip
echo "发布包：$(ls -lh NiecheEmu-macos.zip | awk '{print $5}')  NiecheEmu-macos.zip"
