# DeepSeek.app

把 DeepSeek Harness 的 Web 聊天界面（`http://127.0.0.1:3080`）包装成 macOS 原生桌面应用。

- **零第三方依赖**：仅用系统自带的 Swift + AppKit + WebKit，无需安装任何框架
- **独立窗口**：WKWebView 承载聊天界面，支持缩放、最小化、⌘Q/⌘C/⌘V 等原生快捷键
- **自动拉起服务**：启动时检测 3080 端口，若 `dsh web` 未运行则自动后台拉起
- **服务与 App 解耦**：关闭 App 窗口不会杀掉后台服务，浏览器里 3080 仍可访问

## 环境要求

- macOS 13.0+
- Xcode Command Line Tools（`xcode-select --install`）
- 已安装 [DeepSeek Harness](https://github.com/deepseek-ai)（提供 `dsh web`，监听 3080）

## 构建

```bash
./build.sh
```

产物在 `build/DeepSeek.app`。

## 安装

```bash
cp -R build/DeepSeek.app ~/Applications/
```

然后从启动台 / Finder 双击运行，或拖入 Dock 固定。

## 运行原理

1. 启动时用 Network framework 探测 `127.0.0.1:3080` 是否监听。
2. 若未监听，按以下优先级拉起 `dsh web`：
   - `DSH_BIN` / `DSH_NODE` 环境变量指定的 `dsh`、`node`
   - Homebrew / 系统路径中的 `node` + `dsh`
   - 兜底 `npx @deepseek-ai/dsh web`
3. 轮询等待端口就绪（最多 20 秒），然后加载 `http://127.0.0.1:3080`。

## 环境变量（可选）

| 变量 | 作用 |
|------|------|
| `DSH_BIN` | 指定 `dsh` 可执行文件路径 |
| `DSH_NODE` | 指定 `node` 可执行文件路径 |
| `DSH_NPX` | 指定 `npx` 可执行文件路径 |

## 目录结构

```text
.
├── build.sh          # 一键构建脚本
├── Info.plist        # App 配置
├── Assets/
│   └── whale.png     # 应用图标（1024px）
└── Sources/
    └── main.swift    # Swift 主程序
```

## 已知限制

- App 本身不含 DeepSeek Harness，需先安装并确保 `dsh web` 可运行。
- 服务默认只监听 `127.0.0.1`，App 仅在访问本机服务，不对外暴露。
- 图标取自 DeepSeek 官方鲸鱼 logo（蓝色版转黑色），版权归 DeepSeek 所有。
