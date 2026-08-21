import AppKit
import WebKit

final class BrowserViewController: NSViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    var onCapabilities: (([String]) -> Void)?
    var onLayoutUpdate: ((CGFloat, CGFloat, CGFloat) -> Void)?

    private(set) var webView: WKWebView!
    private let overlay = NSVisualEffectView()
    private let overlayTitle = NSTextField(labelWithString: "")
    private let overlayDetail = NSTextField(wrappingLabelWithString: "")
    private let overlayButton = NSButton(title: "", target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private var retryAction: (() -> Void)?
    private var allowedServiceOrigin: String?

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.userContentController.add(self, name: "dshLayout")
        configuration.userContentController.addUserScript(WKUserScript(
            source: makeCodexThemeInjectionScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true

        let root = NSView()
        root.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.topAnchor.constraint(equalTo: root.topAnchor),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        view = root
        installOverlay()
        showWelcome()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "dshLayout",
              let body = message.body as? [String: Any],
              let sidebarWidth = body["sidebarWidth"] as? NSNumber,
              let contentLeft = body["contentLeft"] as? NSNumber,
              let contentWidth = body["contentWidth"] as? NSNumber else { return }
        onLayoutUpdate?(
            CGFloat(sidebarWidth.doubleValue),
            CGFloat(contentLeft.doubleValue),
            CGFloat(contentWidth.doubleValue)
        )
    }

    func loadService(_ url: URL) {
        allowedServiceOrigin = origin(of: url)
        showLoading(title: "正在连接 DeepSeek Harness…", detail: url.absoluteString)
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData))
    }

    func showServiceFailure(_ message: String, retry: @escaping () -> Void) {
        retryAction = retry
        showOverlay(title: "DeepSeek Harness 暂不可用", detail: message, button: "重新启动", spinning: false)
    }

    func showWorkspaceRequired(choose: @escaping () -> Void) {
        retryAction = choose
        showOverlay(
            title: "选择一个工作区开始",
            detail: "工作区限定 Agent、终端和 Git 操作的默认边界。不会允许使用文件系统根目录。",
            button: "选择文件夹…",
            spinning: false
        )
    }

    func showWelcome() {
        showOverlay(
            title: "DeepSeek Desktop",
            detail: "正在准备本地 Agent 工作台…",
            button: nil,
            spinning: true
        )
    }

    func openDSHSettings() {
        let script = #"""
        (() => {
          const nodes = Array.from(document.querySelectorAll('button,[role="button"],a'));
          const target = nodes.find((node) => {
            const text = `${node.textContent || ''} ${node.getAttribute('aria-label') || ''} ${node.getAttribute('title') || ''}`;
            return /设置|settings/i.test(text);
          });
          if (!target) return false;
          target.click();
          return true;
        })();
        """#
        webView.evaluateJavaScript(script) { [weak self] value, _ in
            if (value as? Bool) != true {
                self?.showTransientMessage("请使用 DSH 左下角的“设置”入口管理模型、权限、插件与 MCP。")
            }
        }
    }

    func focusComposer() {
        webView.evaluateJavaScript("document.querySelector('textarea')?.focus()")
    }

    func toggleConversationSidebar() {
        let script = #"""
        (() => {
          const labels = ['收起侧边栏', '打开侧边栏', 'Collapse sidebar', 'Open sidebar'];
          const button = Array.from(document.querySelectorAll('button')).find(
            (node) => labels.includes(node.getAttribute('aria-label') || '')
          );
          button?.click();
          return Boolean(button);
        })();
        """#
        webView.evaluateJavaScript(script)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, origin(of: url) == allowedServiceOrigin else { return }
        overlay.isHidden = true
        let script = "(window.__DSH_BOOT__?.entries || []).map(entry => entry.id)"
        webView.evaluateJavaScript(script) { [weak self] value, _ in
            self?.onCapabilities?(value as? [String] ?? [])
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        showLoading(title: "正在恢复界面…", detail: "WebContent 进程已退出。")
        webView.reload()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
           origin(of: url) != allowedServiceOrigin {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            if origin(of: url) == allowedServiceOrigin {
                webView.load(URLRequest(url: url))
            } else {
                NSWorkspace.shared.open(url)
            }
        }
        return nil
    }

    private func installOverlay() {
        overlay.material = .contentBackground
        overlay.state = .active
        overlay.blendingMode = .withinWindow
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlayTitle.font = .systemFont(ofSize: 17, weight: .semibold)
        overlayTitle.alignment = .center
        overlayDetail.textColor = .secondaryLabelColor
        overlayDetail.alignment = .center
        overlayDetail.maximumNumberOfLines = 5
        overlayDetail.preferredMaxLayoutWidth = 460
        overlayButton.bezelStyle = .rounded
        overlayButton.controlSize = .large
        overlayButton.target = self
        overlayButton.action = #selector(performRetry)
        spinner.style = .spinning

        let stack = NSStackView(views: [spinner, overlayTitle, overlayDetail, overlayButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(stack)
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: overlay.widthAnchor, constant: -80)
        ])
    }

    private func showLoading(title: String, detail: String) {
        showOverlay(title: title, detail: detail, button: nil, spinning: true)
    }

    private func showOverlay(title: String, detail: String, button: String?, spinning: Bool) {
        overlayTitle.stringValue = title
        overlayDetail.stringValue = detail
        overlayButton.title = button ?? ""
        overlayButton.isHidden = button == nil
        spinner.isHidden = !spinning
        spinning ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
        overlay.isHidden = false
    }

    private func handleNavigationError(_ error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        showServiceFailure(error.localizedDescription) { [weak self] in self?.webView.reload() }
    }

    private func showTransientMessage(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "DSH 设置"
        alert.informativeText = text
        alert.runModal()
    }

    private func origin(of url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }

    @objc private func performRetry() {
        retryAction?()
    }
}
