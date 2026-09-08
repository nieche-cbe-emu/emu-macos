# emu-macos

尼彩 CBE 模拟器的 macOS 外壳（SwiftUI）。

模拟核心跑在**独立子进程**里，和外壳用 stdin/stdout 上的二进制协议通信。
引擎有两个实现，说的是同一套协议：

- [emu-core](https://github.com/nieche-cbe-emu/emu-core) 的 Rust `engine`——默认，
  单个可执行文件，不需要用户机器上有 Python
- 同一仓库里 Python 的 `tools/engine.py`——参照实现，`NIECHE_ENGINE=python` 切回去

找不到 Rust 引擎时会自动回落，并**在日志里说明用的是哪个**。

## 构建

```
./build.sh          # 出 NiecheEmu.app（到上一级目录）
./package.sh        # 再打一个自带引擎的发布包 NiecheEmu-macos.zip
```

需要 Xcode Command Line Tools（`swiftc` 即可，不用完整 Xcode）。
`build.sh` 会把 `emu-core` 构建出来的 Rust `engine` 打进 app；没有就跳过。
`package.sh` 还会把 Python 回落引擎装进 `Resources/pyengine`，
这样下载解压即可运行，不用 clone 仓库也不用 pip 装依赖。

## 说明

本仓库只有代码。游戏数据不在这里，也不会提供。
