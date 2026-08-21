import AppKit

private final class NavigatorNode: NSObject {
    enum Kind {
        case group(String)
        case workspace(WorkspaceRecord)
        case task(TaskRecord)
    }

    let kind: Kind
    var children: [NavigatorNode]

    init(kind: Kind, children: [NavigatorNode] = []) {
        self.kind = kind
        self.children = children
    }
}

final class NavigatorViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var onChooseWorkspace: (() -> Void)?
    var onCreateTask: (() -> Void)?
    var onSelectWorkspace: ((UUID) -> Void)?
    var onSelectTask: ((UUID) -> Void)?
    var onArchiveTask: ((TaskRecord) -> Void)?

    private let store: WorkspaceStore
    private let outlineView = NSOutlineView()
    private var roots: [NavigatorNode] = []
    private var isRestoringSelection = false

    init(store: WorkspaceStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: .workspaceStoreDidChange,
            object: store
        )
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("navigator"))
        column.title = "工作台"
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .medium
        outlineView.style = .sourceList
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(revealSelection)

        let scroll = NSScrollView()
        scroll.documentView = outlineView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let addWorkspace = NSButton(title: "工作区", target: self, action: #selector(chooseWorkspace))
        addWorkspace.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)
        addWorkspace.imagePosition = .imageLeading
        addWorkspace.bezelStyle = .texturedRounded

        let newTask = NSButton(title: "任务", target: self, action: #selector(createTask))
        newTask.image = NSImage(systemSymbolName: "plus.square.on.square", accessibilityDescription: nil)
        newTask.imagePosition = .imageLeading
        newTask.bezelStyle = .texturedRounded

        let bottom = NSStackView(views: [addWorkspace, newTask])
        bottom.orientation = .horizontal
        bottom.distribution = .fillEqually
        bottom.spacing = 8
        bottom.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 10, right: 10)

        let stack = NSStackView(views: [scroll, bottom])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            bottom.heightAnchor.constraint(equalToConstant: 48)
        ])
        view = root
        reload()
    }

    @objc func reload() {
        let workspaceNodes = store.state.workspaces
            .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
            .map { NavigatorNode(kind: .workspace($0)) }
        let taskNodes: [NavigatorNode]
        if let workspace = store.selectedWorkspace {
            taskNodes = store.tasks(for: workspace.id).map { NavigatorNode(kind: .task($0)) }
        } else {
            taskNodes = []
        }
        roots = [
            NavigatorNode(kind: .group("工作区"), children: workspaceNodes),
            NavigatorNode(kind: .group("隔离任务"), children: taskNodes)
        ]
        outlineView.reloadData()
        for root in roots { outlineView.expandItem(root) }
        isRestoringSelection = true
        restoreSelection()
        isRestoringSelection = false
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? NavigatorNode)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? NavigatorNode)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? NavigatorNode else { return false }
        return !node.children.isEmpty
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        guard let node = item as? NavigatorNode else { return false }
        if case .group = node.kind { return true }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let node = item as? NavigatorNode else { return false }
        if case .group = node.kind { return false }
        return true
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? NavigatorNode else { return nil }
        let id = NSUserInterfaceItemIdentifier("navigator-cell")
        let cell = outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id
        if cell.textField == nil {
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingMiddle
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        switch node.kind {
        case let .group(title):
            cell.textField?.stringValue = title
        case let .workspace(workspace):
            cell.textField?.stringValue = workspace.title
            cell.imageView?.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            cell.toolTip = workspace.path
        case let .task(task):
            cell.textField?.stringValue = task.title
            cell.imageView?.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)
            cell.toolTip = "\(task.branch)\n\(task.worktreePath)"
        }
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isRestoringSelection else { return }
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? NavigatorNode else { return }
        switch node.kind {
        case let .workspace(workspace): onSelectWorkspace?(workspace.id)
        case let .task(task): onSelectTask?(task.id)
        case .group: break
        }
    }

    func menu(for event: NSEvent) -> NSMenu? {
        let point = outlineView.convert(event.locationInWindow, from: nil)
        let row = outlineView.row(at: point)
        guard row >= 0, let node = outlineView.item(atRow: row) as? NavigatorNode else { return nil }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        let menu = NSMenu()
        let reveal = NSMenuItem(title: "在 Finder 中显示", action: #selector(revealSelection), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)
        if case .task = node.kind {
            let archive = NSMenuItem(title: "归档任务…", action: #selector(archiveSelection), keyEquivalent: "")
            archive.target = self
            menu.addItem(archive)
        }
        return menu
    }

    private func restoreSelection() {
        let targetID = store.selectedTask?.id ?? store.selectedWorkspace?.id
        guard let targetID else { return }
        for row in 0..<outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: row) as? NavigatorNode else { continue }
            let id: UUID?
            switch node.kind {
            case let .workspace(value): id = value.id
            case let .task(value): id = value.id
            case .group: id = nil
            }
            if id == targetID {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                break
            }
        }
    }

    @objc private func chooseWorkspace() { onChooseWorkspace?() }
    @objc private func createTask() { onCreateTask?() }

    @objc private func revealSelection() {
        guard let node = outlineView.item(atRow: outlineView.selectedRow) as? NavigatorNode else { return }
        switch node.kind {
        case let .workspace(value): NSWorkspace.shared.activateFileViewerSelecting([value.url])
        case let .task(value): NSWorkspace.shared.activateFileViewerSelecting([value.url])
        case .group: break
        }
    }

    @objc private func archiveSelection() {
        guard let node = outlineView.item(atRow: outlineView.selectedRow) as? NavigatorNode,
              case let .task(task) = node.kind else { return }
        onArchiveTask?(task)
    }
}

extension NavigatorViewController {
    override func rightMouseDown(with event: NSEvent) {
        if let menu = menu(for: event) {
            NSMenu.popUpContextMenu(menu, with: event, for: outlineView)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}
