# dsh-confetti-click

DSH 客户端插件：在 Web 界面任意位置**鼠标点击撒花**。

- 纯 vanilla DOM 实现，零依赖、无构建步骤
- 点击处喷出 70–100 片彩屑，带重力、旋转、渐隐，约 1–2 秒落地
- `immediately: true`，页面启动时由 Cordis 应用插件并安装全局 click 监听（capture 阶段，不会被 UI 吞掉）
- 撒花层 `pointer-events: none`，不干扰任何交互

## 热开关（无需重启、无需改配置）

插件带一个运行时开关，浏览器内**即时生效**：

- **🎉 悬浮按钮**：右下角（`right:28px; bottom:104px`）半透明圆形按钮，点击即切换；
  关闭时显示 🚫 并置灰。按钮在设置弹层（z-index 1000）之下，不影响任何交互。
- **快捷键 Alt+Shift+X**：任意时刻切换开关。
- **状态记忆**：保存在 `localStorage["dsh-confetti-click.enabled"]`，刷新页面后保持。

> 为什么能热开关：开关是纯客户端状态，只控制 click 监听是否放行，不触碰
> loader / boot 图 / 配置文件，所以无需重启。改 profile 配置那种禁用是"冷"的——
> web profile 的 HMR 被 `dsh-web-app` 禁用（`hmr: disabled`），配置变更必须重启。

## 平台级开关（设置 → 插件 → 插件列表）

平台功能：插件列表页现在给每个插件卡片提供「已启用 / 已停用」切换按钮。

- **运行时即时生效**：切换调用 `pluginInventory.setEnabled`，服务端对 loader entry
  执行 `Entry.update({disabled})`——禁用即 dispose fiber，启用即重新拉起。
- **重启后保持**：切换结果以 `- id: confetti-click / disabled: <bool>` 的形式写入
  profile 的 `cordis.patch.yml`（注释保留、原子写、跨进程文件锁），下次启动自动应用。
- **保护**：容器条目（`include` 等）不可切换；有活跃依赖方的核心服务（如 storage、
  tools、llm）会被拒绝禁用，防止下次启动因依赖缺失而失败。
- 悬浮按钮/快捷键仍然可用；平台开关与它们互不干扰，平台开关是更权威的形态。

## 目录

```text
plugins/dsh-confetti-click/
├── package.json    # dsh.client 声明（platform: web, immediately: true）
└── lib/
    ├── index.js    # Node/host 端空插件
    └── client.js   # 客户端 bundle：window.__ModuleLoader__.load({id, factory})
```

## 安装（已执行）

```bash
# 1) 装进 web profile（link: 使 node_modules 内为符号链接，改代码即时生效）
dsh plugin --profile web add link:/Users/ore/develop/dsh-app/plugins/dsh-confetti-click

# 2) 在 ~/.dsh/profiles/web/cordis.patch.yml 追加 loader entry：
# - insert:
#     - id: confetti-click
#       name: dsh-confetti-click
```

> 注意：web profile 的 HMR 处于禁用状态（`dsh-web-app` patch 中 `hmr: disabled`），
> loader entry 变更**不会热生效**，需要重启 `dsh web` 并刷新页面。

## 卸载

```bash
dsh plugin --profile web remove dsh-confetti-click
# 并从 cordis.patch.yml 删掉 confetti-click 行
```

## 原理速览

1. `dsh web` 启动时，`dsh-client-modules` 扫描 loader entries 中声明
   `dsh.client`（platform: web）的包，把 `exports["./client"]` 的构建产物哈希进
   `window.__DSH_BOOT__`，并通过 `/plugins/<id>/client.js?rev=<hash>` 提供。
2. 浏览器 shell 启动时对 `immediately: true` 的行做 prefetch + 建 fiber + 物化，
   factory 导出带 `apply()` 的 Cordis 插件；应用插件时注入 `<style>`、挂 click 监听，
   卸载插件时移除监听、动画节点和样式。
3. 每次点击在指针处生成一簇彩屑，rAF 驱动物理动画，结束后移除 DOM 节点。
