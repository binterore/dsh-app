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

/// Reserves the same top strip Codex uses as a native window drag handle.
/// WKWebView consumes mouse events itself, so a transparent AppKit view is
/// required for reliable dragging when the title bar is visually hidden.
final class WindowDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var statusItem: NSStatusItem?
    private var loadTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ensureServerRunning()
        buildMenu()
        buildWindow()
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
        window.backgroundColor = NSColor(calibratedWhite: 0.965, alpha: 1)
        window.center()
        window.minSize = NSSize(width: 480, height: 600)

        let contentView = NSView(frame: .zero)
        let dragView = WindowDragView(frame: .zero)
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
            // Keep only the very top edge draggable so the compact web toolbar
            // immediately below it remains fully interactive.
            dragView.heightAnchor.constraint(equalToConstant: 12)
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
        }

        let menu = NSMenu()
        let openItem = NSMenuItem(
            title: "打开 DeepSeek",
            action: #selector(showMainWindow(_:)),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 DeepSeek",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        item.menu = menu
        statusItem = item
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
}

// MARK: - 入口
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
