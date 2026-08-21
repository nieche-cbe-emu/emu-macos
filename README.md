# emu-macos

尼彩 CBE 模拟器的 macOS 外壳（SwiftUI）。模拟核心是
[emu-core](https://github.com/nieche-cbe-emu/emu-core) 的 Python 引擎子进程，
两者用 stdin/stdout 上的二进制协议通信。

## 构建

```
pip install unicorn capstone
./build.sh
```

需要 Xcode Command Line Tools（`swiftc` 即可，不用完整 Xcode）。
生成的 `NiecheEmu.app` 在上一级目录。

`build.sh` 会把项目目录写进 app 包，运行时据此找到 `tools/engine.py`，
所以 emu-core 和 emu-tools 需要放在同级目录下。

## 功能

游戏库、镜像源下载、存档管理、功能机键盘布局、触屏常驻、
键盘按键可自定义、Scale2x/Scale3x 放大、旋转、MIDI 音频。

模拟器不自带游戏源，镜像源地址需要自己填。
