import AppKit
import SwiftTerm

final class InspectorViewController: NSViewController {
    var onShowChanges: (() -> Void)? {
        didSet { environment.onShowChanges = onShowChanges }
    }
    private let content = NSView()
    private let environment = EnvironmentInfoViewController()

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.codexPanelBackground.cgColor
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        view = root
        addChild(environment)
        environment.view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(environment.view)
        NSLayoutConstraint.activate([
            environment.view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            environment.view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            environment.view.topAnchor.constraint(equalTo: content.topAnchor),
            environment.view.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
    }

    func setWorkspace(_ url: URL?) {
        environment.setWorkspace(url)
    }

    func setCapabilities(_ pluginIDs: [String]) {}

    func refreshChanges() { environment.refresh() }
}

private final class EnvironmentInfoViewController: NSViewController {
    var onShowChanges: (() -> Void)?
    private let git = GitService()
    private let changesValue = NSTextField(labelWithString: "—")
    private let branchButton = NSButton()
    private let branchChevron = NSImageView()
    private let localChevron = NSImageView()
    private var workspace: URL?

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.codexPanelBackground.cgColor

        let title = NSTextField(labelWithString: "环境信息")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .codexPrimaryText
        let add = NSButton(
            image: NSImage(systemSymbolName: "plus", accessibilityDescription: "添加环境")!,
            target: nil,
            action: nil
        )
        add.isBordered = false
        add.contentTintColor = .codexTertiaryText
        let header = NSStackView(views: [title, NSView(), add])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 4, right: 14)
        header.heightAnchor.constraint(equalToConstant: 34).isActive = true

        configureTrailing(changesValue)
        configureChevron(localChevron)
        configureChevron(branchChevron)
        let rows = NSStackView(views: [
            makeRow(symbol: "doc.badge.plus", title: "变更", trailing: changesValue, action: #selector(showChanges)),
            makeRow(symbol: "laptopcomputer", title: "本地", trailing: localChevron, action: nil),
            makeRow(button: branchButton, symbol: "arrow.triangle.branch", title: "—", trailing: branchChevron, action: nil),
            makeRow(symbol: "slider.horizontal.3", title: "提交或推送", trailing: nil, action: #selector(showChanges)),
            makeRow(symbol: "arrow.triangle.pull", title: "无法获取拉取请求状态", trailing: nil, action: nil, emphasized: false)
        ])
        rows.orientation = .vertical
        rows.spacing = 0

        let stack = NSStackView(views: [header, rows])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor)
        ])
        view = root
        refresh()
    }

    func setWorkspace(_ url: URL?) {
        workspace = url
        if isViewLoaded { refresh() }
    }

    func refresh() {
        guard let workspace else {
            branchButton.title = "未选择工作区"
            changesValue.stringValue = "—"
            return
        }
        branchButton.title = "读取分支…"
        changesValue.stringValue = ""
        git.snapshot(at: workspace) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(snapshot):
                self.branchButton.title = snapshot.branch
                if snapshot.changes.isEmpty {
                    self.changesValue.stringValue = "无更改"
                    self.changesValue.textColor = .codexSecondaryText
                } else {
                    let value = NSMutableAttributedString(
                        string: "+\(snapshot.additions.formatted())",
                        attributes: [.foregroundColor: NSColor.codexChangeAdd]
                    )
                    value.append(NSAttributedString(
                        string: " −\(snapshot.deletions.formatted())",
                        attributes: [.foregroundColor: NSColor.codexChangeRemove]
                    ))
                    self.changesValue.attributedStringValue = value
                }
            case .failure:
                self.branchButton.title = "非 Git 工作区"
                self.changesValue.stringValue = "—"
                self.changesValue.textColor = .codexSecondaryText
            }
        }
    }

    private func configureTrailing(_ label: NSTextField) {
        label.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)
        label.textColor = .codexSecondaryText
        label.lineBreakMode = .byTruncatingMiddle
        label.alignment = .right
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func configureChevron(_ chevron: NSImageView) {
        chevron.image = NSImage(
            systemSymbolName: "chevron.right",
            accessibilityDescription: nil
        )
        chevron.contentTintColor = .codexTertiaryText
        chevron.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        chevron.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func makeRow(
        button suppliedButton: NSButton? = nil,
        symbol: String,
        title: String,
        trailing: NSView?,
        action: Selector?,
        emphasized: Bool = true
    ) -> NSView {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        let button = suppliedButton ?? NSButton()
        button.title = title
        button.target = action == nil ? nil : self
        button.action = action
        button.image = image
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.isBordered = false
        button.alignment = .left
        button.font = .systemFont(ofSize: 13, weight: .regular)
        let textColor = emphasized ? NSColor.codexPrimaryText : NSColor.codexSecondaryText
        button.contentTintColor = textColor
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.foregroundColor: textColor]
        )
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let inner = NSStackView(views: [button, spacer] + (trailing.map { [$0] } ?? []))
        inner.orientation = .horizontal
        inner.alignment = .centerY
        inner.spacing = 8
        inner.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 14)
        let row = HoverRow()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(inner)
        inner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            inner.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 33)
        ])
        return row
    }

    @objc private func showChanges() { onShowChanges?() }

}

private final class HoverRow: NSView {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        wantsLayer = true
        layer?.backgroundColor = NSColor.codexHover.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = .clear
    }
}

extension NSColor {
    static let codexPanelBackground = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(
            srgbRed: dark ? 17 / 255.0 : 248 / 255.0,
            green: dark ? 17 / 255.0 : 249 / 255.0,
            blue: dark ? 16 / 255.0 : 252 / 255.0,
            alpha: 1
        )
    }

    static let codexSidebarBackground = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(
            srgbRed: dark ? 23 / 255.0 : 239 / 255.0,
            green: dark ? 23 / 255.0 : 240 / 255.0,
            blue: dark ? 22 / 255.0 : 241 / 255.0,
            alpha: 1
        )
    }

    static let codexPrimaryText = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(
            srgbRed: dark ? 239 / 255.0 : 17 / 255.0,
            green: dark ? 239 / 255.0 : 23 / 255.0,
            blue: dark ? 233 / 255.0 : 37 / 255.0,
            alpha: 1
        )
    }

    static let codexSecondaryText = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(
            srgbRed: dark ? 170 / 255.0 : 108 / 255.0,
            green: dark ? 169 / 255.0 : 113 / 255.0,
            blue: dark ? 161 / 255.0 : 123 / 255.0,
            alpha: 1
        )
    }

    static let codexTertiaryText = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(
            srgbRed: dark ? 121 / 255.0 : 144 / 255.0,
            green: dark ? 121 / 255.0 : 147 / 255.0,
            blue: dark ? 114 / 255.0 : 155 / 255.0,
            alpha: 1
        )
    }

    static let codexHover = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(
            srgbRed: dark ? 1 : 17 / 255.0,
            green: dark ? 1 : 23 / 255.0,
            blue: dark ? 248 / 255.0 : 37 / 255.0,
            alpha: dark ? 0.075 : 0.055
        )
    }

    static let codexChangeAdd = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(
            srgbRed: dark ? 52 / 255.0 : 22 / 255.0,
            green: dark ? 209 / 255.0 : 153 / 255.0,
            blue: dark ? 88 / 255.0 : 65 / 255.0,
            alpha: 1
        )
    }

    static let codexChangeRemove = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(
            srgbRed: dark ? 255 / 255.0 : 208 / 255.0,
            green: dark ? 69 / 255.0 : 32 / 255.0,
            blue: dark ? 58 / 255.0 : 32 / 255.0,
            alpha: 1
        )
    }

    static let codexTerminalBackground = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(
            srgbRed: dark ? 17 / 255.0 : 247 / 255.0,
            green: dark ? 17 / 255.0 : 249 / 255.0,
            blue: dark ? 16 / 255.0 : 252 / 255.0,
            alpha: 1
        )
    }

    static let codexTerminalText = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(
            srgbRed: dark ? 239 / 255.0 : 17 / 255.0,
            green: dark ? 239 / 255.0 : 23 / 255.0,
            blue: dark ? 233 / 255.0 : 37 / 255.0,
            alpha: 1
        )
    }
}

final class ChangesViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onClose: (() -> Void)?
    private let git = GitService()
    private let branchLabel = NSTextField(labelWithString: "未选择 Git 工作区")
    private let table = NSTableView()
    private let diffText = NSTextView()
    private var workspace: URL?
    private var snapshot: GitSnapshot?

    override func loadView() {
        let root = NSView()
        branchLabel.font = .systemFont(ofSize: 12, weight: .medium)
        branchLabel.lineBreakMode = .byTruncatingMiddle

        let refresh = button(symbol: "arrow.clockwise", toolTip: "刷新", action: #selector(refreshAction))
        let stage = button(symbol: "plus", toolTip: "暂存", action: #selector(stageSelection))
        let unstage = button(symbol: "minus", toolTip: "取消暂存", action: #selector(unstageSelection))
        let discard = button(symbol: "trash", toolTip: "放弃更改", action: #selector(discardSelection))
        let commit = button(symbol: "checkmark.circle", toolTip: "提交已暂存更改", action: #selector(commitChanges))
        let back = button(symbol: "xmark", toolTip: "关闭变更面板", action: #selector(closeDetail))
        let header = NSStackView(views: [back, branchLabel, NSView(), refresh])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6
        branchLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [NSView(), stage, unstage, discard, commit])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 6
        let toolbar = NSStackView(views: [header, actions])
        toolbar.orientation = .vertical
        toolbar.spacing = 4

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("change"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowSizeStyle = .medium
        table.allowsMultipleSelection = true
        table.dataSource = self
        table.delegate = self
        let tableScroll = NSScrollView()
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true

        diffText.isEditable = false
        diffText.isRichText = false
        diffText.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        diffText.textContainerInset = NSSize(width: 10, height: 10)
        diffText.string = "选择一个文件查看 Diff。"
        let diffScroll = NSScrollView()
        diffScroll.documentView = diffText
        diffScroll.hasVerticalScroller = true
        diffScroll.hasHorizontalScroller = true

        let split = NSSplitView()
        split.isVertical = false
        split.dividerStyle = .thin
        split.addArrangedSubview(tableScroll)
        split.addArrangedSubview(diffScroll)
        tableScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true

        let stack = NSStackView(views: [toolbar, split])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 60)
        ])
        view = root
        if workspace != nil { self.refresh() }
    }

    func setWorkspace(_ url: URL?) {
        workspace = url
        refresh()
    }

    func refresh() {
        guard isViewLoaded, let workspace else {
            snapshot = nil
            table.reloadData()
            branchLabel.stringValue = "未选择工作区"
            return
        }
        branchLabel.stringValue = "正在读取 Git…"
        git.snapshot(at: workspace) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(snapshot):
                self.snapshot = snapshot
                let divergence = [snapshot.ahead > 0 ? "↑\(snapshot.ahead)" : nil,
                                  snapshot.behind > 0 ? "↓\(snapshot.behind)" : nil]
                    .compactMap { $0 }.joined(separator: " ")
                self.branchLabel.stringValue = divergence.isEmpty ? snapshot.branch : "\(snapshot.branch) · \(divergence)"
                self.table.reloadData()
                if snapshot.changes.isEmpty { self.diffText.string = "工作区干净。" }
            case let .failure(error):
                self.snapshot = nil
                self.table.reloadData()
                self.branchLabel.stringValue = "非 Git 工作区"
                self.diffText.string = error.localizedDescription
            }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { snapshot?.changes.count ?? 0 }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let change = snapshot?.changes[row] else { return nil }
        let id = NSUserInterfaceItemIdentifier("change-cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id
        if cell.textField == nil {
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingMiddle
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        cell.textField?.stringValue = "\(change.displayStatus)  \(change.path)"
        cell.textField?.textColor = change.isStaged ? .systemGreen : .labelColor
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard table.selectedRow >= 0,
              let snapshot,
              table.selectedRow < snapshot.changes.count else { return }
        let change = snapshot.changes[table.selectedRow]
        diffText.string = "正在生成 Diff…"
        git.diff(for: change, at: snapshot.root) { [weak self] result in
            switch result {
            case let .success(text): self?.diffText.string = text.isEmpty ? "没有可显示的文本 Diff。" : text
            case let .failure(error): self?.diffText.string = error.localizedDescription
            }
        }
    }

    private var selectedChanges: [GitChange] {
        guard let snapshot else { return [] }
        return table.selectedRowIndexes.compactMap { index in
            index < snapshot.changes.count ? snapshot.changes[index] : nil
        }
    }

    private func button(symbol: String, toolTip: String, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)!, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.toolTip = toolTip
        return button
    }

    @objc private func refreshAction() { refresh() }
    @objc private func closeDetail() { onClose?() }

    @objc private func stageSelection() {
        guard let snapshot else { return }
        let paths = selectedChanges.map(\.path)
        guard !paths.isEmpty else { return }
        git.stage(paths, at: snapshot.root) { [weak self] result in self?.finishMutation(result) }
    }

    @objc private func unstageSelection() {
        guard let snapshot else { return }
        let paths = selectedChanges.map(\.path)
        guard !paths.isEmpty else { return }
        git.unstage(paths, at: snapshot.root) { [weak self] result in self?.finishMutation(result) }
    }

    @objc private func discardSelection() {
        guard let snapshot else { return }
        let changes = selectedChanges
        guard !changes.isEmpty else { return }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "放弃选中的本地更改？"
        alert.informativeText = "这会恢复已跟踪文件并永久删除选中的未跟踪文件，无法撤销。"
        alert.addButton(withTitle: "放弃更改")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        git.discard(changes, at: snapshot.root) { [weak self] result in self?.finishMutation(result) }
    }

    @objc private func commitChanges() {
        guard let snapshot else { return }
        let alert = NSAlert()
        alert.messageText = "提交已暂存更改"
        alert.informativeText = "Commit message 使用 `xxx: yyy` 格式。"
        let input = NSTextField(string: "feat: ")
        input.frame = NSRect(x: 0, y: 0, width: 380, height: 24)
        alert.accessoryView = input
        alert.addButton(withTitle: "提交")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let message = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.range(of: #"^[a-z]+: .+"#, options: .regularExpression) != nil else {
            showMutationError(CommandError.couldNotLaunch("Commit message 必须符合 `xxx: yyy` 格式。"))
            return
        }
        git.commit(message: message, at: snapshot.root) { [weak self] result in
            switch result {
            case .success: self?.refresh()
            case let .failure(error): self?.showMutationError(error)
            }
        }
    }

    private func finishMutation(_ result: Result<Void, Error>) {
        switch result {
        case .success: refresh()
        case let .failure(error): showMutationError(error)
        }
    }

    private func showMutationError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

final class TerminalViewController: NSViewController {
    var onClose: (() -> Void)?
    private let terminalView = LocalProcessTerminalView(frame: .zero)
    private let gutterSidebar = NSView()
    private let gutterMargin = NSView()
    private var gutterSidebarWidth: NSLayoutConstraint?
    private var gutterMarginWidth: NSLayoutConstraint?
    private var terminalWidth: NSLayoutConstraint?
    private var stackLeadingToGutter: NSLayoutConstraint?
    private var stackLeadingToRoot: NSLayoutConstraint?
    private var stackTrailingToRoot: NSLayoutConstraint?
    private var workspace: URL?

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.codexTerminalBackground.cgColor

        gutterSidebar.wantsLayer = true
        gutterSidebar.layer?.backgroundColor = NSColor.codexSidebarBackground.cgColor
        gutterSidebar.translatesAutoresizingMaskIntoConstraints = false
        gutterMargin.wantsLayer = true
        gutterMargin.layer?.backgroundColor = NSColor.codexTerminalBackground.cgColor
        gutterMargin.translatesAutoresizingMaskIntoConstraints = false

        terminalView.nativeBackgroundColor = .codexTerminalBackground
        terminalView.nativeForegroundColor = .codexTerminalText
        terminalView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        terminalView.translatesAutoresizingMaskIntoConstraints = false

        let back = NSButton(
            image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "收起终端")!,
            target: self,
            action: #selector(closeDetail)
        )
        back.bezelStyle = .texturedRounded
        back.contentTintColor = .codexSecondaryText
        let title = NSTextField(labelWithString: "终端")
        title.font = .systemFont(ofSize: 12.5, weight: .semibold)
        title.textColor = .codexPrimaryText
        let clear = NSButton(
            image: NSImage(systemSymbolName: "trash", accessibilityDescription: "清空终端")!,
            target: self,
            action: #selector(clearOutput)
        )
        clear.bezelStyle = .texturedRounded
        clear.contentTintColor = .codexSecondaryText
        clear.toolTip = "清空终端（⌃L）"
        let header = NSStackView(views: [back, title, NSView(), clear])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6
        header.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)

        let stack: NSStackView = NSStackView(views: [header, terminalView])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(gutterSidebar)
        root.addSubview(gutterMargin)
        root.addSubview(stack)
        let sidebarWidthConstraint = gutterSidebar.widthAnchor.constraint(equalToConstant: 0)
        let marginWidthConstraint = gutterMargin.widthAnchor.constraint(equalToConstant: 0)
        let terminalWidthConstraint = stack.widthAnchor.constraint(equalToConstant: 0)
        gutterSidebarWidth = sidebarWidthConstraint
        gutterMarginWidth = marginWidthConstraint
        terminalWidth = terminalWidthConstraint
        let leadingToGutter = stack.leadingAnchor.constraint(equalTo: gutterMargin.trailingAnchor)
        let leadingToRoot = stack.leadingAnchor.constraint(equalTo: root.leadingAnchor)
        let trailingToRoot = stack.trailingAnchor.constraint(equalTo: root.trailingAnchor)
        stackLeadingToGutter = leadingToGutter
        stackLeadingToRoot = leadingToRoot
        stackTrailingToRoot = trailingToRoot
        // Default: terminal fills the whole drawer so it is never invisible,
        // even before the page reports its layout.
        leadingToRoot.isActive = true
        trailingToRoot.isActive = true
        NSLayoutConstraint.activate([
            gutterSidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            gutterSidebar.topAnchor.constraint(equalTo: root.topAnchor),
            gutterSidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebarWidthConstraint,
            gutterMargin.leadingAnchor.constraint(equalTo: gutterSidebar.trailingAnchor),
            gutterMargin.topAnchor.constraint(equalTo: root.topAnchor),
            gutterMargin.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            marginWidthConstraint,
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            header.heightAnchor.constraint(equalToConstant: 28)
        ])
        // Gutter and width constraints stay inactive until the page reports
        // its real layout.
        leadingToGutter.isActive = false
        terminalWidthConstraint.isActive = false
        view = root
        if let workspace {
            start(in: workspace)
        }
    }

    func setLayout(
        sidebarWidth: CGFloat,
        contentLeft: CGFloat,
        contentWidth: CGFloat
    ) {
        let sidebar = max(0, sidebarWidth)
        let left = max(sidebar, contentLeft)
        gutterSidebarWidth?.constant = sidebar
        gutterMarginWidth?.constant = max(0, left - sidebar)
        terminalWidth?.constant = max(0, contentWidth)
        gutterSidebar.layer?.backgroundColor = NSColor.codexSidebarBackground.cgColor
        gutterMargin.layer?.backgroundColor = NSColor.codexTerminalBackground.cgColor
        if contentWidth > 0 {
            stackLeadingToRoot?.isActive = false
            stackTrailingToRoot?.isActive = false
            stackLeadingToGutter?.isActive = true
            terminalWidth?.isActive = true
        }
    }

    func setWorkspace(_ url: URL?) {
        guard workspace != url else { return }
        workspace = url
        guard isViewLoaded else { return }
        if let url {
            start(in: url)
        } else {
            terminalView.terminate()
        }
    }

    func focusInput() {
        guard isViewLoaded else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self else { return }
            self.view.window?.makeFirstResponder(self.terminalView)
        }
    }

    @objc func clearOutput() {
        guard isViewLoaded else { return }
        // Authentic Ctrl+L: hand the byte to the shell so it clears the screen.
        terminalView.terminal.sendUserInput(ArraySlice([0x0c]))
    }

    private func start(in url: URL) {
        terminalView.terminate()
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["NO_COLOR"] = "1"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let preferred = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.cargo/bin"]
        let inherited = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = (preferred + [inherited]).joined(separator: ":")
        let envList = environment.map { "\($0.key)=\($0.value)" }
        terminalView.startProcess(
            executable: "/bin/zsh",
            args: [],
            environment: envList,
            execName: nil as String?,
            currentDirectory: url.path
        )
    }

    @objc private func closeDetail() { onClose?() }
}

private final class ActivityViewController: NSViewController {
    private let text = NSTextView()

    override func loadView() {
        text.isEditable = false
        text.isRichText = false
        text.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        text.textContainerInset = NSSize(width: 8, height: 8)
        let scroll = NSScrollView()
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        view = scroll
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: .appLogDidChange,
            object: nil
        )
        reload()
    }

    @objc private func reload() {
        text.string = AppLogger.shared.recentText()
        text.scrollToEndOfDocument(nil)
    }
}
