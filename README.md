# emu-macos

尼彩 CBE 模拟器的 macOS 外壳（SwiftUI）。

模拟核心是 [emu-core-rs](https://github.com/nieche-cbe-emu/emu-core-rs) 的
`engine`，跑在**独立子进程**里，和外壳用 stdin/stdout 上的二进制协议通信。

**只跑 Rust 核心，没有回落。** 以前找不到就悄悄换成 Python 参照实现，
慢十几倍，而用户只会觉得机器卡、根本不知道跑的不是同一个东西。
现在找不到就直接报错。

## 构建

```
./build.sh          # 出 NiecheEmu.app（到上一级目录）
./package.sh        # 再打一个自带引擎的发布包 NiecheEmu-macos.zip
```

需要 Xcode Command Line Tools（`swiftc` 即可，不用完整 Xcode）。
`build.sh` 会把 emu-core-rs 构建出来的 `engine` 打进 app 的
`Resources/engine`，下载解压即可运行。

## 帧率

工具栏里的「帧率」是**游戏速度**，不只是画面流畅度：模块的动画和计时
都是按帧推进的，跑多快游戏就多快。默认 30；真机上这些游戏大概只有
10–15 fps，觉得太快就往下调。

## 说明

本仓库只有代码。游戏数据不在这里，也不会提供。
