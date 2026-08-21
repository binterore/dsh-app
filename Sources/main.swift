import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSToolbarDelegate, NSMenuItemValidation {
    private let store = WorkspaceStore()
    private let service = DSHServiceManager()
    private let git = GitService()
    private let updater = UpdaterManager.shared
    private lazy var workbench = WorkbenchViewController(store: store)
    private lazy var settingsController = SettingsWindowController()
    private var window: NSWindow!
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var serviceToolbarItem: NSToolbarItem?
    private var inspectorToggleButton: NSButton?
    private var lastReadyURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? AppPaths.ensureDirectories()
        AppLogger.shared.log("DeepSeek Desktop 启动", category: "lifecycle")
        migrateWorkbenchLayoutIfNeeded()
        buildMenu()
        buildWindow()
        bindControllers()
        updateInspectorToggleState()
        buildStatusItem()
        NotificationManager.shared.requestAuthorization()
        updater.start()
        restoreInitialWorkspace()
    }

    private func migrateWorkbenchLayoutIfNeeded() {
        let key = "DeepSeekDesktop.WorkbenchLayoutVersion"
        guard UserDefaults.standard.integer(forKey: key) < 3 else { return }
        // Version 1 opened two native split panes around DSH's own sidebar and
        // conversation surface. Codex uses one primary interaction layer, so
        // start the new layout focused and let the user reveal utilities.
        store.setNavigatorVisible(false)
        store.setInspectorVisible(false)
        UserDefaults.standard.set(3, forKey: key)
    }

    func applicationWillTerminate(_ notification: Notification) {
        service.stop()
        AppLogger.shared.log("DeepSeek Desktop 退出", category: "lifecycle")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow(nil)
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "deepseek-desktop" {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let path = components.queryItems?.first(where: { $0.name == "path" })?.value else { continue }
            do {
                _ = try store.addWorkspace(URL(fileURLWithPath: path))
                activateCurrentRoot()
            } catch { presentError(error) }
        }
    }

    private func buildWindow() {
        // Match the Codex desktop app's default window proportions (~1548x920)
        // and open on the largest display, like Codex does.
        let screen = NSScreen.screens.max(by: {
            $0.visibleFrame.width * $0.visibleFrame.height
                < $1.visibleFrame.width * $1.visibleFrame.height
        }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(1560, max(1100, visible.width * 0.76))
        let height = min(940, max(720, visible.height * 0.82))
        let rect = NSRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "DeepSeek Desktop"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 920, height: 640)
        // Assigning the split-view workbench first; AppKit would otherwise
        // shrink the window to the split view's minimum (920x640) after the
        // frame below is applied.
        window.contentViewController = workbench
        // v2 frame name: the old 1.x layout saved a small window; Codex-sized
        // default should not be overridden by that stale frame.
        window.setFrame(rect, display: false)
        if !window.setFrameUsingName("DeepSeekDesktop.MainWindow.v2") { window.center() }
        window.setFrameAutosaveName("DeepSeekDesktop.MainWindow.v2")

        // Codex keeps the titlebar to the traffic lights; the workbench
        // utilities live behind keyboard shortcuts and menus instead of an
        // icon toolbar.
        installInspectorToggle()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installInspectorToggle() {
        let button = NSButton(
            image: NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: "环境信息")!,
            target: self,
            action: #selector(toggleInspector(_:))
        )
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = "环境信息（⌘⇧I）"
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 34, height: 28))
        button.frame = container.bounds
        container.addSubview(button)
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .trailing
        accessory.view = container
        window.addTitlebarAccessoryViewController(accessory)
        inspectorToggleButton = button
    }

    private func updateInspectorToggleState() {
        let visible = workbench.isInspectorVisible
        inspectorToggleButton?.contentTintColor = visible
            ? .labelColor
            : .secondaryLabelColor
        inspectorToggleButton?.toolTip = visible
            ? "隐藏环境信息（⌘⇧I）"
            : "环境信息（⌘⇧I）"
    }

    private func bindControllers() {
        workbench.navigator.onChooseWorkspace = { [weak self] in self?.chooseWorkspace(nil) }
        workbench.navigator.onCreateTask = { [weak self] in self?.createTask(nil) }
        workbench.navigator.onSelectWorkspace = { [weak self] id in
            self?.store.selectWorkspace(id)
            self?.activateCurrentRoot()
        }
        workbench.navigator.onSelectTask = { [weak self] id in
            self?.store.selectTask(id)
            self?.activateCurrentRoot()
        }
        workbench.navigator.onArchiveTask = { [weak self] task in self?.archiveTask(task) }
        workbench.browser.onCapabilities = { [weak self] ids in self?.workbench.inspector.setCapabilities(ids) }
        settingsController.onOpenDSHSettings = { [weak self] in
            self?.showMainWindow(nil)
            self?.workbench.browser.openDSHSettings()
        }
        service.onStateChange = { [weak self] state in self?.handleServiceState(state) }
    }

    private func restoreInitialWorkspace() {
        if let override = ProcessInfo.processInfo.environment["DSH_WORKSPACE"], !override.isEmpty {
            do { _ = try store.addWorkspace(URL(fileURLWithPath: override)) }
            catch { presentError(error) }
        }
        guard store.activeRoot != nil else {
            workbench.browser.showWorkspaceRequired { [weak self] in self?.chooseWorkspace(nil) }
            return
        }
        activateCurrentRoot()
    }

    private func activateCurrentRoot() {
        guard let root = store.activeRoot else {
            workbench.browser.showWorkspaceRequired { [weak self] in self?.chooseWorkspace(nil) }
            return
        }
        do {
            let validated = try WorkspacePolicy.validate(root)
            workbench.setWorkspace(validated)
            window.representedURL = validated
            window.subtitle = store.selectedTask.map { "\($0.title) · \($0.branch)" } ?? validated.path
            lastReadyURL = nil
            service.start(workspace: validated)
        } catch { presentError(error) }
    }

    private func handleServiceState(_ state: DSHServiceState) {
        updateServiceUI(state)
        switch state {
        case let .ready(url):
            if lastReadyURL != url {
                lastReadyURL = url
                workbench.browser.loadService(url)
            }
        case let .failed(message):
            workbench.browser.showServiceFailure(message) { [weak self] in self?.service.restart() }
            NotificationManager.shared.post(title: "DeepSeek Harness 启动失败", body: message)
        case .starting, .restarting, .stopped:
            break
        }
    }

    private func updateServiceUI(_ state: DSHServiceState) {
        serviceToolbarItem?.label = state.displayText
        serviceToolbarItem?.toolTip = state.displayText
        statusMenu?.item(withTag: 100)?.title = "DeepSeek Harness：\(state.displayText)"
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let icon = NSImage(named: "AppIcon") ?? NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
            icon?.size = NSSize(width: 18, height: 18)
            icon?.isTemplate = true
            button.image = icon
            button.toolTip = "DeepSeek Desktop"
            button.target = self
            button.action = #selector(handleStatusClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        let menu = NSMenu()
        let show = NSMenuItem(title: "显示 DeepSeek Desktop", action: #selector(showMainWindow(_:)), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let status = NSMenuItem(title: "DeepSeek Harness：未运行", action: nil, keyEquivalent: "")
        status.tag = 100
        status.isEnabled = false
        menu.addItem(status)
        let restart = NSMenuItem(title: "重启受管服务", action: #selector(restartService(_:)), keyEquivalent: "")
        restart.target = self
        menu.addItem(restart)
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem = item
        statusMenu = menu
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let app = NSMenu()
        app.addItem(withTitle: "关于 DeepSeek Desktop", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let settings = NSMenuItem(title: "设置…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settings.target = self
        app.addItem(settings)
        let updates = NSMenuItem(title: "检查更新…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        updates.target = self
        app.addItem(updates)
        app.addItem(.separator())
        app.addItem(withTitle: "隐藏 DeepSeek Desktop", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "退出 DeepSeek Desktop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let file = NSMenu(title: "文件")
        let open = NSMenuItem(title: "添加工作区…", action: #selector(chooseWorkspace(_:)), keyEquivalent: "o")
        open.target = self
        file.addItem(open)
        let task = NSMenuItem(title: "新建隔离任务…", action: #selector(createTask(_:)), keyEquivalent: "n")
        task.keyEquivalentModifierMask = [.command, .shift]
        task.target = self
        file.addItem(task)
        file.addItem(.separator())
        file.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = file
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let viewItem = NSMenuItem()
        let view = NSMenu(title: "显示")
        let navigator = NSMenuItem(title: "切换任务导航", action: #selector(toggleNavigator(_:)), keyEquivalent: "b")
        navigator.target = self
        view.addItem(navigator)
        let inspector = NSMenuItem(title: "切换工作台检查器", action: #selector(toggleInspector(_:)), keyEquivalent: "i")
        inspector.keyEquivalentModifierMask = [.command, .shift]
        inspector.target = self
        view.addItem(inspector)
        let changes = NSMenuItem(title: "切换变更审查", action: #selector(toggleChanges(_:)), keyEquivalent: "r")
        changes.keyEquivalentModifierMask = [.command, .shift]
        changes.target = self
        view.addItem(changes)
        let terminal = NSMenuItem(title: "切换底部终端", action: #selector(showTerminal(_:)), keyEquivalent: "j")
        terminal.target = self
        view.addItem(terminal)
        let clearTerminal = NSMenuItem(title: "清空终端", action: #selector(clearTerminal(_:)), keyEquivalent: "l")
        clearTerminal.keyEquivalentModifierMask = [.control]
        clearTerminal.target = self
        view.addItem(clearTerminal)
        let focus = NSMenuItem(title: "聚焦输入框", action: #selector(focusComposer(_:)), keyEquivalent: "l")
        focus.target = self
        view.addItem(focus)
        viewItem.submenu = view
        main.addItem(viewItem)

        let agentItem = NSMenuItem()
        let agent = NSMenu(title: "Agent")
        let dshSettings = NSMenuItem(title: "模型、权限、Skills、插件与 MCP…", action: #selector(openDSHSettings(_:)), keyEquivalent: "")
        dshSettings.target = self
        agent.addItem(dshSettings)
        let restart = NSMenuItem(title: "重启受管 DSH", action: #selector(restartService(_:)), keyEquivalent: "r")
        restart.keyEquivalentModifierMask = [.command, .option]
        restart.target = self
        agent.addItem(restart)
        agentItem.submenu = agent
        main.addItem(agentItem)

        let helpItem = NSMenuItem()
        let help = NSMenu(title: "帮助")
        let diagnostics = NSMenuItem(title: "导出诊断包…", action: #selector(exportDiagnostics(_:)), keyEquivalent: "")
        diagnostics.target = self
        help.addItem(diagnostics)
        helpItem.submenu = help
        main.addItem(helpItem)
        NSApp.mainMenu = main
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .flexibleSpace, .openLocation, .changes, .terminal, .service, .toggleInspector]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if id == .openLocation {
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = "打开位置"
            item.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)
            item.showsIndicator = true
            let menu = NSMenu()
            let finder = NSMenuItem(title: "在 Finder 中显示", action: #selector(revealActiveRoot(_:)), keyEquivalent: "")
            finder.target = self
            menu.addItem(finder)
            let terminal = NSMenuItem(title: "在终端中打开", action: #selector(openActiveRootInTerminal(_:)), keyEquivalent: "")
            terminal.target = self
            menu.addItem(terminal)
            let code = NSMenuItem(title: "在 Visual Studio Code 中打开", action: #selector(openActiveRootInVSCode(_:)), keyEquivalent: "")
            code.target = self
            menu.addItem(code)
            item.menu = menu
            return item
        }
        let item = NSToolbarItem(itemIdentifier: id)
        switch id {
        case .toggleSidebar:
            item.label = "工作区与隔离任务"; item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil); item.action = #selector(toggleNavigator(_:))
        case .service:
            item.label = "DSH"; item.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: nil); item.action = #selector(restartService(_:)); serviceToolbarItem = item
        case .changes:
            item.label = "变更"; item.image = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: nil); item.action = #selector(toggleChanges(_:))
        case .terminal:
            item.label = "终端"; item.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil); item.action = #selector(showTerminal(_:))
        case .toggleInspector:
            item.label = "检查器"; item.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: nil); item.action = #selector(toggleInspector(_:))
        default: return nil
        }
        item.target = self
        return item
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates(_:)) { return updater.isConfigured }
        if menuItem.action == #selector(createTask(_:)) { return store.selectedWorkspace != nil }
        return true
    }

    @objc private func chooseWorkspace(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "选择 Agent 工作区"
        panel.prompt = "添加工作区"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.selectedWorkspace?.url ?? FileManager.default.homeDirectoryForCurrentUser
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                _ = try self.store.addWorkspace(url)
                self.activateCurrentRoot()
            } catch { self.presentError(error) }
        }
    }

    @objc private func createTask(_ sender: Any?) {
        guard let workspace = store.selectedWorkspace else { return }
        let alert = NSAlert()
        alert.messageText = "新建隔离任务"
        alert.informativeText = "为任务创建独立 Git worktree 和 `codex/` 分支。"
        let title = NSTextField(string: "")
        title.placeholderString = "任务名称"
        let branch = NSTextField(string: "")
        branch.placeholderString = "分支名（可选）"
        let fields = NSStackView(views: [title, branch])
        fields.orientation = .vertical
        fields.spacing = 8
        fields.frame = NSRect(x: 0, y: 0, width: 380, height: 56)
        alert.accessoryView = fields
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let taskTitle = title.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !taskTitle.isEmpty else { return }
        git.createWorktree(
            workspace: workspace,
            title: taskTitle,
            requestedBranch: branch.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        ) { [weak self] result in
            switch result {
            case let .success(task): self?.store.appendTask(task); self?.activateCurrentRoot()
            case let .failure(error): self?.presentError(error)
            }
        }
    }

    private func archiveTask(_ task: TaskRecord) {
        guard let workspace = store.state.workspaces.first(where: { $0.id == task.workspaceID }) else { return }
        let alert = NSAlert()
        alert.messageText = "归档“\(task.title)”？"
        alert.informativeText = "可以只从导航中归档，也可以同时移除干净的 Git worktree。含未提交更改的 worktree 不会被删除。"
        alert.addButton(withTitle: "归档并保留文件")
        alert.addButton(withTitle: "归档并移除干净工作树")
        alert.addButton(withTitle: "取消")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            store.archiveTask(task.id)
            activateCurrentRoot()
        } else if response == .alertSecondButtonReturn {
            git.removeWorktree(task, workspace: workspace) { [weak self] result in
                switch result {
                case .success: self?.store.archiveTask(task.id); self?.activateCurrentRoot()
                case let .failure(error): self?.presentError(error)
                }
            }
        }
    }

    @objc private func handleStatusClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            guard let statusItem, let statusMenu else { return }
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else { showMainWindow(sender) }
    }

    @objc private func showMainWindow(_ sender: Any?) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleNavigator(_ sender: Any?) {
        workbench.toggleNavigator()
    }
    @objc private func toggleInspector(_ sender: Any?) {
        workbench.toggleInspector()
        store.setInspectorVisible(workbench.isInspectorVisible)
        updateInspectorToggleState()
    }
    @objc private func toggleChanges(_ sender: Any?) {
        workbench.toggleChanges()
    }
    @objc private func showTerminal(_ sender: Any?) {
        workbench.toggleTerminal()
    }
    @objc private func clearTerminal(_ sender: Any?) {
        workbench.clearTerminal()
    }
    @objc private func focusComposer(_ sender: Any?) { workbench.browser.focusComposer() }
    @objc private func openDSHSettings(_ sender: Any?) { workbench.browser.openDSHSettings() }
    @objc private func restartService(_ sender: Any?) { lastReadyURL = nil; service.restart() }
    @objc private func showSettings(_ sender: Any?) { settingsController.showWindow(sender) }
    @objc private func checkForUpdates(_ sender: Any?) { updater.checkForUpdates() }

    @objc private func revealActiveRoot(_ sender: Any?) {
        guard let root = store.activeRoot else { return }
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }

    @objc private func openActiveRootInTerminal(_ sender: Any?) {
        openActiveRoot(withBundleIdentifier: "com.apple.Terminal")
    }

    @objc private func openActiveRootInVSCode(_ sender: Any?) {
        openActiveRoot(withBundleIdentifier: "com.microsoft.VSCode")
    }

    private func openActiveRoot(withBundleIdentifier identifier: String) {
        guard let root = store.activeRoot,
              let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(
            [root],
            withApplicationAt: application,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    @objc private func exportDiagnostics(_ sender: Any?) {
        AppLogger.shared.makeDiagnosticsArchive(workspace: store.activeRoot) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(url):
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.zip]
                panel.nameFieldStringValue = url.lastPathComponent
                panel.beginSheetModal(for: self.window) { response in
                    guard response == .OK, let destination = panel.url else { return }
                    do {
                        if FileManager.default.fileExists(atPath: destination.path) {
                            try FileManager.default.removeItem(at: destination)
                        }
                        try FileManager.default.copyItem(at: url, to: destination)
                    } catch { self.presentError(error) }
                }
            case let .failure(error): self.presentError(error)
            }
        }
    }

    private func presentError(_ error: Error) {
        AppLogger.shared.log(error.localizedDescription, category: "error")
        let alert = NSAlert(error: error)
        if let window { alert.beginSheetModal(for: window) }
        else { alert.runModal() }
    }
}

private extension NSToolbarItem.Identifier {
    static let toggleSidebar = NSToolbarItem.Identifier("DeepSeekDesktop.toggleSidebar")
    static let openLocation = NSToolbarItem.Identifier("DeepSeekDesktop.openLocation")
    static let workspace = NSToolbarItem.Identifier("DeepSeekDesktop.workspace")
    static let newTask = NSToolbarItem.Identifier("DeepSeekDesktop.newTask")
    static let service = NSToolbarItem.Identifier("DeepSeekDesktop.service")
    static let settings = NSToolbarItem.Identifier("DeepSeekDesktop.settings")
    static let changes = NSToolbarItem.Identifier("DeepSeekDesktop.changes")
    static let terminal = NSToolbarItem.Identifier("DeepSeekDesktop.terminal")
    static let toggleInspector = NSToolbarItem.Identifier("DeepSeekDesktop.toggleInspector")
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) {
        app.run()
    }
}
