import AppKit

final class WorkbenchViewController: NSSplitViewController {
    let navigator: NavigatorViewController
    let browser = BrowserViewController()
    let inspector = InspectorViewController()

    private let changes = ChangesViewController()
    private let terminal = TerminalViewController()
    private let changesItem: NSSplitViewItem
    private let terminalItem: NSSplitViewItem
    private let inspectorItem: NSSplitViewItem

    init(store: WorkspaceStore) {
        navigator = NavigatorViewController(store: store)

        let reviewSplit = NSSplitViewController()
        reviewSplit.splitView.isVertical = true
        reviewSplit.splitView.dividerStyle = .thin
        let browserItem = NSSplitViewItem(viewController: browser)
        browserItem.minimumThickness = 560
        changesItem = NSSplitViewItem(viewController: changes)
        changesItem.minimumThickness = 360
        changesItem.maximumThickness = 720
        changesItem.preferredThicknessFraction = 0.34
        changesItem.canCollapse = true
        reviewSplit.addSplitViewItem(browserItem)
        reviewSplit.addSplitViewItem(changesItem)

        // The terminal drawer docks under the conversation column only; the
        // environment panel on the right stays full height.
        let contentSplit = NSSplitViewController()
        contentSplit.splitView.isVertical = false
        contentSplit.splitView.dividerStyle = .thin
        let reviewItem = NSSplitViewItem(viewController: reviewSplit)
        reviewItem.minimumThickness = 360
        terminalItem = NSSplitViewItem(viewController: terminal)
        terminalItem.minimumThickness = 170
        terminalItem.maximumThickness = 520
        terminalItem.preferredThicknessFraction = 0.28
        terminalItem.canCollapse = true
        contentSplit.addSplitViewItem(reviewItem)
        contentSplit.addSplitViewItem(terminalItem)

        let contentItem = NSSplitViewItem(viewController: contentSplit)
        contentItem.minimumThickness = 620
        inspectorItem = NSSplitViewItem(inspectorWithViewController: inspector)
        inspectorItem.minimumThickness = 300
        inspectorItem.maximumThickness = 420
        inspectorItem.preferredThicknessFraction = 0.23
        inspectorItem.canCollapse = true

        super.init(nibName: nil, bundle: nil)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        addSplitViewItem(contentItem)
        addSplitViewItem(inspectorItem)

        changesItem.isCollapsed = true
        terminalItem.isCollapsed = true
        inspectorItem.isCollapsed = !store.state.inspectorVisible

        changes.onClose = { [weak self] in self?.setChangesVisible(false) }
        terminal.onClose = { [weak self] in self?.setTerminalVisible(false) }
        inspector.onShowChanges = { [weak self] in self?.setChangesVisible(true) }
        browser.onLayoutUpdate = { [weak terminal] sidebar, left, width in
            terminal?.setLayout(
                sidebarWidth: sidebar,
                contentLeft: left,
                contentWidth: width
            )
        }
    }

    required init?(coder: NSCoder) { nil }

    var isInspectorVisible: Bool { !inspectorItem.isCollapsed }
    var isChangesVisible: Bool { !changesItem.isCollapsed }
    var isTerminalVisible: Bool { !terminalItem.isCollapsed }

    func setWorkspace(_ url: URL?) {
        inspector.setWorkspace(url)
        changes.setWorkspace(url)
        terminal.setWorkspace(url)
    }

    func refreshChanges() {
        inspector.refreshChanges()
        changes.refresh()
    }

    func toggleNavigator() { browser.toggleConversationSidebar() }
    func toggleInspector() { inspectorItem.animator().isCollapsed.toggle() }

    func toggleChanges() {
        setChangesVisible(!isChangesVisible)
    }

    func toggleTerminal() {
        setTerminalVisible(!isTerminalVisible)
        if isTerminalVisible { terminal.focusInput() }
    }

    func clearTerminal() {
        terminal.clearOutput()
    }

    private func setChangesVisible(_ visible: Bool) {
        changesItem.animator().isCollapsed = !visible
        if visible { changes.refresh() }
    }

    private func setTerminalVisible(_ visible: Bool) {
        terminalItem.animator().isCollapsed = !visible
    }
}
