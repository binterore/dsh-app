import Foundation
import Darwin

enum DSHServiceState: Equatable {
    case stopped
    case starting(String)
    case ready(URL)
    case restarting(Int)
    case failed(String)

    var displayText: String {
        switch self {
        case .stopped: return "未运行"
        case .starting: return "正在启动"
        case let .ready(url): return "运行中 · \(url.port ?? 0)"
        case let .restarting(attempt): return "正在恢复 · \(attempt)/3"
        case .failed: return "启动失败"
        }
    }
}

private struct DSHLaunchCommand {
    let executable: URL
    let arguments: [String]
    let description: String
}

final class DSHServiceManager {
    static let pinnedVersion = "0.1.0-rc.7"

    var onStateChange: ((DSHServiceState) -> Void)?
    var onOutput: ((String) -> Void)?

    private let queue = DispatchQueue(label: "com.deepseek.desktop.service", qos: .userInitiated)
    private var process: Process?
    private var processGroup: pid_t?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var stdoutBuffer = ""
    private var generation = UUID()
    private var desiredWorkspace: URL?
    private var intentionalStop = false
    private var recoveryAttempts = 0
    private var healthFailures = 0
    private(set) var state: DSHServiceState = .stopped
    private(set) var serviceURL: URL?

    deinit {
        stop()
    }

    func start(workspace: URL) {
        queue.async {
            do {
                let validated = try WorkspacePolicy.validate(workspace)
                self.desiredWorkspace = validated
                self.recoveryAttempts = 0
                self.startLocked(workspace: validated, recovery: false)
            } catch {
                self.transition(.failed(error.localizedDescription))
            }
        }
    }

    func restart() {
        queue.async {
            guard let workspace = self.desiredWorkspace else {
                self.transition(.failed("尚未选择工作区。"))
                return
            }
            self.recoveryAttempts = 0
            self.startLocked(workspace: workspace, recovery: false)
        }
    }

    func stop() {
        queue.async {
            self.generation = UUID()
            self.intentionalStop = true
            self.stopOwnedProcessLocked()
            self.serviceURL = nil
            self.transition(.stopped)
        }
    }

    private func startLocked(workspace: URL, recovery: Bool) {
        generation = UUID()
        let launchGeneration = generation
        intentionalStop = true
        stopOwnedProcessLocked()
        intentionalStop = false
        stdoutBuffer = ""
        healthFailures = 0
        serviceURL = nil

        let launch: DSHLaunchCommand
        do {
            launch = try resolveLaunchCommand()
        } catch {
            transition(.failed(error.localizedDescription))
            return
        }

        transition(recovery ? .restarting(recoveryAttempts) : .starting(launch.description))
        AppLogger.shared.log(
            "启动受管 DSH：\(launch.description)，workspace=\(workspace.path)",
            category: "service"
        )

        let task = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.executableURL = launch.executable
        task.arguments = launch.arguments
        task.currentDirectoryURL = workspace
        var environment = ProcessInfo.processInfo.environment
        let inheritedPath = environment["PATH"] ?? ""
        environment["PATH"] = [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin", inheritedPath
        ].filter { !$0.isEmpty }.joined(separator: ":")
        environment["DSH_DESKTOP_INSTANCE"] = launchGeneration.uuidString
        environment["DSH_DESKTOP_WORKSPACE"] = workspace.path
        task.environment = environment
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.queue.async { self?.consumeOutputLocked(text, generation: launchGeneration) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.queue.async { self?.publishOutput(text, category: "dsh.stderr") }
        }
        task.terminationHandler = { [weak self] terminated in
            self?.queue.async {
                guard let self, self.generation == launchGeneration else { return }
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                self.stdoutHandle = nil
                self.stderrHandle = nil
                self.process = nil
                self.processGroup = nil
                self.serviceURL = nil
                if self.intentionalStop {
                    self.transition(.stopped)
                } else {
                    self.handleUnexpectedExitLocked(status: terminated.terminationStatus)
                }
            }
        }

        do {
            try task.run()
            process = task
            stdoutHandle = stdoutPipe.fileHandleForReading
            stderrHandle = stderrPipe.fileHandleForReading
            let pid = pid_t(task.processIdentifier)
            if setpgid(pid, pid) == 0 {
                processGroup = pid
            } else {
                processGroup = nil
            }
            AppLogger.shared.log("DSH 进程 pid=\(pid)", category: "service")
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            transition(.failed("无法启动 DSH：\(error.localizedDescription)"))
            return
        }

        queue.asyncAfter(deadline: .now() + 90) { [weak self] in
            guard let self, self.generation == launchGeneration else { return }
            guard case .ready = self.state else {
                self.publishOutput("DSH 在 90 秒内未报告可用地址。\n", category: "service")
                self.handleFailureLocked("DSH 启动超时。")
                return
            }
        }
    }

    private func consumeOutputLocked(_ text: String, generation: UUID) {
        guard self.generation == generation else { return }
        publishOutput(text, category: "dsh.stdout")
        stdoutBuffer.append(text)
        if stdoutBuffer.count > 32_000 {
            stdoutBuffer = String(stdoutBuffer.suffix(32_000))
        }
        guard serviceURL == nil, let url = extractServiceURL(from: stdoutBuffer) else { return }
        verifyIdentity(url: url, generation: generation)
    }

    private func extractServiceURL(from output: String) -> URL? {
        guard let regex = try? NSRegularExpression(
            pattern: #"dsh web:\s+(http://127\.0\.0\.1:\d+)"#
        ) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              let urlRange = Range(match.range(at: 1), in: output) else { return nil }
        return URL(string: String(output[urlRange]))
    }

    private func verifyIdentity(url: URL, generation: UUID) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            self?.queue.async {
                guard let self, self.generation == generation else { return }
                guard error == nil,
                      let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      let data,
                      let html = String(data: data, encoding: .utf8),
                      html.contains("__DSH_BOOT__"),
                      html.contains("DeepSeek Harness") else {
                    self.handleFailureLocked("子进程返回的页面不是有效的 DeepSeek Harness。")
                    return
                }
                self.serviceURL = url
                self.recoveryAttempts = 0
                self.healthFailures = 0
                self.transition(.ready(url))
                self.scheduleHealthCheck(generation: generation)
            }
        }.resume()
    }

    private func scheduleHealthCheck(generation: UUID) {
        queue.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.generation == generation, let url = self.serviceURL else { return }
            var request = URLRequest(url: url)
            request.timeoutInterval = 4
            request.httpMethod = "GET"
            URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
                self?.queue.async {
                    guard let self, self.generation == generation else { return }
                    if error == nil,
                       let http = response as? HTTPURLResponse,
                       (200..<500).contains(http.statusCode) {
                        self.healthFailures = 0
                        self.scheduleHealthCheck(generation: generation)
                    } else {
                        self.healthFailures += 1
                        if self.healthFailures >= 3 {
                            self.handleFailureLocked("DSH 连续三次健康检查失败。")
                        } else {
                            self.scheduleHealthCheck(generation: generation)
                        }
                    }
                }
            }.resume()
        }
    }

    private func handleUnexpectedExitLocked(status: Int32) {
        publishOutput("DSH 进程异常退出，状态码 \(status)。\n", category: "service")
        handleFailureLocked("DSH 进程异常退出（\(status)）。")
    }

    private func handleFailureLocked(_ message: String) {
        intentionalStop = true
        stopOwnedProcessLocked()
        intentionalStop = false
        guard recoveryAttempts < 3, let workspace = desiredWorkspace else {
            transition(.failed(message))
            return
        }
        recoveryAttempts += 1
        transition(.restarting(recoveryAttempts))
        let delay = min(8.0, pow(2.0, Double(recoveryAttempts - 1)))
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.desiredWorkspace == workspace else { return }
            self.startLocked(workspace: workspace, recovery: true)
        }
    }

    private func stopOwnedProcessLocked() {
        guard let task = process else { return }
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        stdoutHandle = nil
        stderrHandle = nil
        let group = processGroup
        let pid = pid_t(task.processIdentifier)
        if task.isRunning {
            if let group {
                kill(-group, SIGTERM)
            } else {
                task.terminate()
            }
            queue.asyncAfter(deadline: .now() + 2) {
                if kill(pid, 0) == 0 {
                    if let group {
                        kill(-group, SIGKILL)
                    } else {
                        kill(pid, SIGKILL)
                    }
                }
            }
        }
        process = nil
        processGroup = nil
    }

    private func resolveLaunchCommand() throws -> DSHLaunchCommand {
        let flags = ["web", "--host", "127.0.0.1", "--port", "0"]
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["DSH_BIN"], FileManager.default.isExecutableFile(atPath: override) {
            return DSHLaunchCommand(
                executable: URL(fileURLWithPath: override),
                arguments: flags,
                description: "DSH_BIN 覆盖"
            )
        }

        if let bundled = bundledDSHScript(), let node = resolveExecutable(named: "node") {
            return DSHLaunchCommand(
                executable: node,
                arguments: [bundled.path] + flags,
                description: "内置 DSH \(Self.pinnedVersion)"
            )
        }

        if let cached = cachedNpxDSHScript(), let node = resolveExecutable(named: "node") {
            return DSHLaunchCommand(
                executable: node,
                arguments: [cached.path] + flags,
                description: "固定版本 DSH \(Self.pinnedVersion)（本机缓存）"
            )
        }

        if let installed = resolveExecutable(named: "dsh"), isPinnedDSH(installed) {
            return DSHLaunchCommand(
                executable: installed,
                arguments: flags,
                description: "已安装 DSH"
            )
        }

        if let npx = resolveExecutable(named: "npx") {
            return DSHLaunchCommand(
                executable: npx,
                arguments: ["--yes", "@deepseek-ai/dsh@\(Self.pinnedVersion)"] + flags,
                description: "固定版本 DSH \(Self.pinnedVersion)（npx）"
            )
        }
        throw CommandError.couldNotLaunch("找不到内置 DSH，也找不到 node、dsh 或 npx。")
    }

    private func isPinnedDSH(_ executable: URL) -> Bool {
        let result = CommandRunner.runSync(
            executable: executable,
            arguments: ["--version"],
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
        let version = (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = result.status == 0 && version.contains(Self.pinnedVersion)
        if !matches {
            AppLogger.shared.log(
                "忽略未固定版本的 dsh：\(executable.path)（报告 \(version)）",
                category: "service"
            )
        }
        return matches
    }

    private func bundledDSHScript() -> URL? {
        let candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent("dsh-runtime/node_modules/@deepseek-ai/dsh/lib/bin.js"),
            AppPaths.runtimeDirectory
                .appendingPathComponent("node_modules/@deepseek-ai/dsh/lib/bin.js")
        ].compactMap { $0 }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func cachedNpxDSHScript() -> URL? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".npm/_npx", isDirectory: true)
        guard let caches = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for cache in caches {
            let package = cache.appendingPathComponent("node_modules/@deepseek-ai/dsh/package.json")
            let script = cache.appendingPathComponent("node_modules/@deepseek-ai/dsh/lib/bin.js")
            let appBoot = cache.appendingPathComponent("node_modules/@deepseek-ai/dsh-app-boot/package.json")
            guard let data = try? Data(contentsOf: package),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["version"] as? String == Self.pinnedVersion,
                  FileManager.default.fileExists(atPath: script.path),
                  FileManager.default.fileExists(atPath: appBoot.path) else { continue }
            return script
        }
        return nil
    }

    private func resolveExecutable(named name: String) -> URL? {
        let environment = ProcessInfo.processInfo.environment
        let directories = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] +
            (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for directory in directories {
            let path = URL(fileURLWithPath: directory).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private func transition(_ newState: DSHServiceState) {
        state = newState
        AppLogger.shared.log("状态：\(newState.displayText)", category: "service")
        DispatchQueue.main.async { [weak self] in self?.onStateChange?(newState) }
    }

    private func publishOutput(_ text: String, category: String) {
        let trimmed = text.trimmingCharacters(in: .newlines)
        if !trimmed.isEmpty { AppLogger.shared.log(trimmed, category: category) }
        DispatchQueue.main.async { [weak self] in self?.onOutput?(text) }
    }
}
