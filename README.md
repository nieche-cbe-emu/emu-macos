# emu-macos

CoolBar `.cbe` 模拟器的 macOS 外壳（SwiftUI）。窗口、绘制、键盘鼠标输入与
计时在原生侧；模拟核心是
[emu-core-rs](https://github.com/nieche-cbe-emu/emu-core-rs) 的 `engine`，
以独立子进程运行，两者用 stdin/stdout 上的二进制协议通信。

## 特性

- 键盘与虚拟键盘输入，鼠标点击映射为触摸
- 缩放、旋转、多种放大算法
- 帧率可任意设定，并显示实测帧率
- 游戏库：记录用过的模块
- 音频交由系统合成器播放（MIDI 走 `AVMIDIPlayer`）

## 安装

应用以 ad-hoc 方式签名，未使用 Developer ID，也未经 Apple 公证。首次打开时
macOS 会拦下并提示无法验证开发者。解除隔离属性后即可打开：

```bash
xattr -dr com.apple.quarantine /Applications/NiecheEmu.app
```

也可在「系统设置 → 隐私与安全性」中对该应用点「仍要打开」。

## 环境要求

- macOS 13.0 及以上，Apple Silicon
- Xcode Command Line Tools（只需 `swiftc`）
- [emu-core-rs](https://github.com/nieche-cbe-emu/emu-core-rs) 已构建

## 构建

```bash
./build.sh      # 生成 ../NiecheEmu.app，并把 engine 打进 Resources/
./package.sh    # 再打成 ../NiecheEmu-macos.zip
```

`build.sh` 按以下顺序查找 `engine`：app 包内 `Resources/engine`、
`../rust/target/release/engine`、`$CARGO_TARGET_DIR/release/engine`、
`~/.cache/nieche-rust/release/engine`。找不到则启动时报错。

## 环境变量

| 变量 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `NIECHE_HOME` | 路径 | 应用支持目录 | 数据根：存档与模块虚拟文件系统 |
| `NIECHE_DIR` | 路径 | 见 `Resources/project_dir` | 项目目录，用于定位资源 |
| `NIECHE_MODULE` | 路径 | 无 | 启动时直接加载该模块 |
| `NIECHE_UPSCALE` | 字符串 | `nearest` | 放大算法，取 `Scale2x` 等 |
| `NIECHE_SNAPSHOT` | 路径 | 无 | 把指定帧写成 PNG 后退出 |
| `NIECHE_SNAPSHOT_FRAME` | 整数 | `20` | 配合上一项，指定第几帧 |

## 帧率

模块的动画与计时按帧推进，帧率直接决定游戏快慢。原机运行这些模块约
10–15 fps。控制区可直接输入任意帧率（1–240），旁边与画面下方显示实测值。

## 说明

本仓库只包含代码。游戏数据不在此处，也不提供。
