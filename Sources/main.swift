import Cocoa
import WebKit
import Network

// MARK: - 配置

let chatURL = URL(string: "http://127.0.0.1:3080")!
let serverCheckHost = "127.0.0.1"
let serverCheckPort: UInt16 = 3080

/// 通过环境变量或常见路径解析可执行文件，避免硬编码机器路径。
/// 优先顺序：环境变量覆盖 > Homebrew(Apple Silicon / Intel) > 系统路径 > PATH。
func resolveExecutable(envKey: String, _ names: [String]) -> String? {
    if let override = ProcessInfo.processInfo.environment[envKey], !override.isEmpty {
        if FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
    }
    let prefixes = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
    for prefix in prefixes {
        for name in names {
            let p = "\(prefix)/\(name)"
            if FileManager.default.isExecutableFile(atPath: p) {
                return p
            }
        }
    }
    for name in names {
        if let found = which(name) {
            return found
        }
    }
    return nil
}

/// 等价 `which`：用 shell 在 PATH 里查找命令。
func which(_ name: String) -> String? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    task.arguments = ["-c", "command -v \(name)"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    do {
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (path?.isEmpty == false) ? path : nil
    } catch {
        return nil
    }
}

// MARK: - 端口探测

func isPortOpen(host: String, port: UInt16) -> Bool {
    let conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    let sem = DispatchSemaphore(value: 0)
    var ok = false
    conn.stateUpdateHandler = { state in
        switch state {
        case .ready:
            ok = true
            sem.signal()
        case .failed, .cancelled:
            sem.signal()
        default:
            break
        }
    }
    let queue = DispatchQueue(label: "portcheck")
    conn.start(queue: queue)
    _ = sem.wait(timeout: .now() + 1.0)
    conn.cancel()
    return ok
}

/// 如果 3080 未监听，就启动 `dsh web` 后台进程。
/// 启动方式优先级：DSH_BIN 环境变量 > node + dsh 可执行文件 > npx。
func ensureServerRunning() {
    if isPortOpen(host: serverCheckHost, port: serverCheckPort) {
        NSLog("3080 已在监听，无需启动 dsh web")
        return
    }
    NSLog("3080 未监听，正在启动 dsh web …")

    var args: [String] = []
    var exec: String? = nil

    if let dshBin = resolveExecutable(envKey: "DSH_BIN", ["dsh"]),
       let nodeBin = resolveExecutable(envKey: "DSH_NODE", ["node"]) {
        // 用 node 直接运行 dsh 脚本，避免 shebang 依赖 PATH
        exec = nodeBin
        args = [dshBin, "web"]
    } else if let npxBin = resolveExecutable(envKey: "DSH_NPX", ["npx"]) {
        exec = npxBin
        args = ["@deepseek-ai/dsh", "web"]
    }

    guard let executable = exec else {
        NSLog("无法找到 node/npx/dsh 可执行文件，请先安装 DeepSeek Harness")
        return
    }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: executable)
    task.arguments = args
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    task.environment = env
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    do {
        try task.run()
        NSLog("已启动 dsh web (pid=\(task.processIdentifier))")
    } catch {
        NSLog("启动 dsh web 失败: \(error)")
    }
}

// MARK: - App

/// 占位视图：hitTest 恒为 nil，不拦截任何鼠标事件——点击、选择、滚动
/// 全部直接交给 WKWebView。拖窗完全由 AppDelegate 的事件监视器完成：
/// 按下后移动超过阈值（12pt）才拖窗，纯点击永远不拖，
/// 因此按钮、输入框、链接绝对可点，页面性能也不受影响。
final class WindowDragView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var dragView: WindowDragView!
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var loadTimer: Timer?
    private var dragMouseDownMonitor: Any?
    private var dragDownEvent: NSEvent?
    private var dragDownWindowPoint: NSPoint?
    private var dragArmed = false

    /// 诊断日志写文件：NSLog/os_log 在非 Apple 签名进程里会被隐私机制
    /// 替换成 <private>，log show 看不到内容，所以拖拽探针的验证日志落到
    /// /tmp/dsh-drag.log，方便排查。
    private func dragLog(_ message: String) {
        let line = "\(Date()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: "/tmp/dsh-drag.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("DeepSeek.app 启动（拖拽诊断构建）")
        dragLog("DeepSeek.app 启动（拖拽诊断构建）")
        ensureServerRunning()
        buildMenu()
        buildWindow()
        installDragProbe()
        buildStatusItem()
        startLoading()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep the menu-bar entry alive so the main window can be reopened.
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow(nil)
        return true
    }

    private func buildWindow() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()  // 持久化 cookie/localStorage
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.userContentController.addUserScript(
            WKUserScript(
                source: makeCodexThemeInjectionScript(),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        config.userContentController.addUserScript(
            WKUserScript(
                source: makeDragProbeScript(),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true

        let rect = NSRect(x: 0, y: 0, width: 1280, height: 820)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "DeepSeek"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        // The status-bar menu reuses this window after it has been closed.
        // AppKit otherwise releases the native window and leaves the retained
        // Swift reference pointing at a deallocated Objective-C object.
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(calibratedWhite: 0.965, alpha: 1)
        window.center()
        window.minSize = NSSize(width: 480, height: 600)

        let contentView = NSView(frame: .zero)
        dragView = WindowDragView(frame: .zero)
        webView.translatesAutoresizingMaskIntoConstraints = false
        dragView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(webView)
        contentView.addSubview(dragView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: contentView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            dragView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            dragView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            dragView.topAnchor.constraint(equalTo: contentView.topAnchor),
            dragView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let icon = NSImage(named: NSImage.Name("AppIcon"))
            icon?.size = NSSize(width: 18, height: 18)
            icon?.isTemplate = true
            button.image = icon
            button.imagePosition = .imageOnly
            button.toolTip = "DeepSeek"
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let menu = NSMenu()
        let showItem = NSMenuItem(
            title: "显示 DeepSeek",
            action: #selector(showMainWindow(_:)),
            keyEquivalent: ""
        )
        showItem.target = self
        showItem.image = nil
        menu.addItem(showItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出",
            action: #selector(quitFromStatusItem(_:)),
            keyEquivalent: ""
        )
        quitItem.target = self
        quitItem.image = nil
        menu.addItem(quitItem)
        statusMenu = menu
        statusItem = item
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            guard let statusItem, let statusMenu else { return }
            // Let AppKit position the menu from the real status-item anchor.
            // Manual NSMenu coordinates place the popup to the icon's left.
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        showMainWindow(sender)
    }

    @objc private func quitFromStatusItem(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    @objc private func showMainWindow(_ sender: Any?) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 DeepSeek",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 DeepSeek",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 DeepSeek",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "显示")
        let toggleSidebarItem = NSMenuItem(
            title: "切换侧边栏",
            action: #selector(toggleSidebar(_:)),
            keyEquivalent: "b"
        )
        toggleSidebarItem.target = self
        toggleSidebarItem.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(toggleSidebarItem)
        viewMenuItem.submenu = viewMenu

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    /// Mirrors Codex's native Command-B shortcut. Keeping this in AppKit makes
    /// the command reliable even while a text field inside WKWebView has focus.
    @objc private func toggleSidebar(_ sender: Any?) {
        guard webView != nil else { return }
        let script = #"""
        (() => {
          const button = document.querySelector(
            '[class*="_sidebarCol"] button[class*="_toggle"]'
          );
          if (!button) return false;
          button.click();
          return true;
        })();
        """#
        webView.evaluateJavaScript(script) { _, error in
            if let error {
                NSLog("切换侧边栏失败：\(error.localizedDescription)")
            }
        }
    }

    private func startLoading() {
        // 轮询等待端口就绪后再加载
        var attempts = 0
        loadTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            attempts += 1
            if isPortOpen(host: serverCheckHost, port: serverCheckPort) {
                timer.invalidate()
                self.loadTimer = nil
                self.webView.load(URLRequest(url: chatURL))
            } else if attempts > 40 {  // 20 秒超时
                timer.invalidate()
                self.loadTimer = nil
                self.webView.load(URLRequest(url: chatURL))  // 尝试加载，即便可能失败
            }
        }
    }

    // 新窗口/弹窗统一在当前 webView 打开
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        dragLog("拖拽诊断: didFinish 触发")
    }

    // MARK: - 拖拽探针

    /// 注入 `window.__dshDragState(el)`：判断某点属于哪类区域。
    /// 返回 0 = 交互元素（按钮/链接/输入/可编辑）—— 永不拖窗；
    /// 返回 2 = 纯文本 —— 仅顶部条带内可拖（保护正文文本选择）；
    /// 返回 1 = 空白 —— 任何位置都可拖。
    /// 注意：文本检查只记录不中断——按钮内的文本必须继续向上找到
    /// button/role/cursor:pointer 父级并判为 0，否则条带内的按钮会被
    /// 误判成文本而拦截点击。
    /// 原生侧在鼠标移动时用 elementFromPoint 查询它，决定该点是否可拖窗。
    private func makeDragProbeScript() -> String {
        return #"""
        (() => {
          if (window.__dshDragState) return;
          window.__dshDragState = (el) => {
            let node = el;
            let sawText = false;
            for (let i = 0; i < 8 && node && node !== document.body && node !== document.documentElement; i += 1) {
              const tag = (node.tagName || '').toLowerCase();
              if (tag === 'a' || tag === 'button' || tag === 'input' || tag === 'textarea' || tag === 'select' || tag === 'label') return 0;
              if (node.isContentEditable) return 0;
              const role = node.getAttribute ? node.getAttribute('role') : null;
              if (role && ['button','tab','treeitem','menuitem','link','textbox','searchbox','checkbox','switch','option','combobox','slider','radio'].includes(role)) return 0;
              if (getComputedStyle(node).cursor === 'pointer') return 0;
              for (const child of node.childNodes) {
                if (child.nodeType === 3 && child.textContent.trim().length > 0) sawText = true;
              }
              node = node.parentElement;
            }
            return sawText ? 2 : 1;
          };
        })();
        """#
    }

    /// 监听鼠标事件驱动拖窗：所有事件都继续分发给 webView（点击/选择/
    /// 滚动不受影响），仅在按下后移动超过阈值时执行窗口拖动。
    /// 不在鼠标移动时做任何探测——高频 evaluateJavaScript + getComputedStyle
    /// 会拖慢页面主线程（按钮点击变得迟钝）；改为按下瞬间探测一次。
    private func installDragProbe() {
        dragMouseDownMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handleDragMouseEvent(event)
            return event
        }
    }

    /// 计算鼠标事件的 CSS y 坐标（页面坐标系，从顶部往下）。
    /// 注意：WKWebView 是 flipped 视图，`convert` 到 webView 坐标后 y 已经
    /// 是从顶部往下的值；若再减一次高度就会上下镜像，导致探针查询错位。
    private func dragCSSY(for event: NSEvent) -> CGFloat {
        guard let webView else { return 0 }
        let point = webView.convert(event.locationInWindow, from: nil)
        if webView.isFlipped {
            return max(0, point.y)
        }
        return max(0, webView.bounds.height - point.y)
    }

    /// 按下→记录并按探测结果武装拖拽；拖动→超阈值执行拖窗；抬起→复位。
    /// 事件始终放行给页面，纯点击不受影响。
    /// 可拖判定：空白(state=1)全窗口可拖；顶部 64pt 内文本(state=2)可拖；
    /// 正文文本与交互元素(state=0)永不拖（保护文本选择与按钮点击）。
    private func handleDragMouseEvent(_ event: NSEvent) {
        guard let window, let webView else { return }
        switch event.type {
        case .leftMouseDown:
            dragDownEvent = event
            dragDownWindowPoint = event.locationInWindow
            let cssY = dragCSSY(for: event)
            dragArmed = false   // 等待按下点探测结果再决定
            let js = "(function(){var el=document.elementFromPoint(\(event.locationInWindow.x), \(cssY));return el?(window.__dshDragState?window.__dshDragState(el):-1):-1})()"
            webView.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self else { return }
                if let number = result as? NSNumber {
                    let state = number.intValue
                    // state==-1 探针不可用：保守允许拖窗
                    let armed = (state == -1) || (state == 1) || (state == 2 && cssY <= 64)
                    self.dragArmed = armed
                    self.dragLog("探测@DOWN: state=\(state) cssY=\(Int(cssY)) armed=\(armed)")
                } else {
                    self.dragArmed = true   // 探测失败：保守允许拖窗
                }
            }
            dragLog("DOWN @(\(Int(event.locationInWindow.x)),\(Int(event.locationInWindow.y))) cssY=\(Int(cssY)) armed=\(dragArmed)")
        case .leftMouseDragged:
            guard dragArmed, let down = dragDownEvent, let p = dragDownWindowPoint else { return }
            let dx = event.locationInWindow.x - p.x
            let dy = event.locationInWindow.y - p.y
            if abs(dx) + abs(dy) > 12 {   // 阈值：区分点击与拖动（含手抖余量）
                dragArmed = false
                dragLog("DRAG 触发拖窗 @(\(Int(event.locationInWindow.x)),\(Int(event.locationInWindow.y)))")
                window.performDrag(with: down)
            }
        case .leftMouseUp:
            dragDownEvent = nil
            dragDownWindowPoint = nil
            dragArmed = false
        default:
            break
        }
    }
}

// MARK: - 入口
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
