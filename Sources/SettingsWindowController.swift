import AppKit

final class SettingsWindowController: NSWindowController {
    var onOpenDSHSettings: (() -> Void)?

    private let updater = UpdaterManager.shared
    private let updateStatus = NSTextField(wrappingLabelWithString: "")
    private let automaticUpdates = NSButton(checkboxWithTitle: "自动检查更新", target: nil, action: nil)

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "DeepSeek 设置"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
    }

    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        refresh()
        super.showWindow(sender)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContent() {
        guard let window, let contentView = window.contentView else { return }
        let title = NSTextField(labelWithString: "DeepSeek Desktop")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "local"
        let subtitle = NSTextField(labelWithString: "版本 \(version)（\(build)） · DSH \(DSHServiceManager.pinnedVersion)")
        subtitle.textColor = .secondaryLabelColor

        let dshTitle = NSTextField(labelWithString: "Agent 与安全")
        dshTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        let dshDescription = NSTextField(wrappingLabelWithString: "模型、Workspace Write / Full Access、Skills、插件、MCP 与自动化由 DSH 设置统一管理。新会话建议使用 Workspace Write。")
        dshDescription.textColor = .secondaryLabelColor
        let dshButton = NSButton(title: "打开 DSH 设置…", target: self, action: #selector(openDSHSettings))
        dshButton.bezelStyle = .rounded

        let updateTitle = NSTextField(labelWithString: "软件更新")
        updateTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        updateStatus.textColor = .secondaryLabelColor
        automaticUpdates.target = self
        automaticUpdates.action = #selector(toggleAutomaticUpdates)
        let check = NSButton(title: "检查更新…", target: self, action: #selector(checkForUpdates))
        check.bezelStyle = .rounded
        check.isEnabled = updater.isConfigured

        let updateRow = NSStackView(views: [automaticUpdates, check])
        updateRow.orientation = .horizontal
        updateRow.spacing = 12
        let stack = NSStackView(views: [
            title, subtitle,
            separator(), dshTitle, dshDescription, dshButton,
            separator(), updateTitle, updateStatus, updateRow
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
            dshDescription.widthAnchor.constraint(equalToConstant: 450),
            updateStatus.widthAnchor.constraint(equalToConstant: 450)
        ])
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 450).isActive = true
        return box
    }

    private func refresh() {
        if updater.isConfigured {
            updateStatus.stringValue = "使用 Sparkle 2 从签名 appcast 获取更新。"
            automaticUpdates.isEnabled = true
            automaticUpdates.state = updater.automaticallyChecksForUpdates ? .on : .off
        } else {
            updateStatus.stringValue = "当前构建未注入 Sparkle Ed25519 公钥；发布构建会强制校验该配置。"
            automaticUpdates.isEnabled = false
            automaticUpdates.state = .off
        }
    }

    @objc private func openDSHSettings() {
        window?.orderOut(nil)
        onOpenDSHSettings?()
    }

    @objc private func toggleAutomaticUpdates() {
        guard updater.isConfigured else { return }
        updater.automaticallyChecksForUpdates = automaticUpdates.state == .on
    }

    @objc private func checkForUpdates() { updater.checkForUpdates() }
}
