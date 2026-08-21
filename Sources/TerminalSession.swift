import Foundation
import Darwin

final class TerminalSession {
    var onOutput: ((String) -> Void)?
    var onExit: ((Int32) -> Void)?

    private let queue = DispatchQueue(label: "com.deepseek.desktop.terminal", qos: .userInitiated)
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private(set) var workingDirectory: URL?

    func start(in directory: URL) {
        stop()
        workingDirectory = directory
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        // `script` owns a real pseudo terminal. A shell connected directly to
        // Foundation pipes is non-interactive, so prompts, line editing and
        // control characters do not behave like a desktop terminal.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null", "/bin/zsh", "-f"]
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "dumb"
        environment["NO_COLOR"] = "1"
        environment["CLICOLOR"] = "0"
        environment["PS1"] = "%1~ %# "
        environment["RPROMPT"] = ""
        environment["PROMPT_EOL_MARK"] = ""
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let preferredPaths = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.cargo/bin"]
        let inheritedPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = (preferredPaths + [inheritedPath]).joined(separator: ":")
        process.environment = environment
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading
        output?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            let cleaned = Self.cleanTerminalOutput(text)
            DispatchQueue.main.async { self?.onOutput?(cleaned) }
        }
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async { self?.onExit?(process.terminationStatus) }
        }
        do {
            try process.run()
            self.process = process
            send("pwd")
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.onOutput?("无法启动终端：\(error.localizedDescription)\n")
            }
        }
    }

    func send(_ command: String) {
        queue.async {
            // Return from a real terminal is carriage return, not line feed.
            guard let data = (command + "\r").data(using: .utf8) else { return }
            do {
                try self.input?.write(contentsOf: data)
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.onOutput?("终端写入失败：\(error.localizedDescription)\n")
                }
            }
        }
    }

    func interrupt() {
        queue.async {
            do {
                try self.input?.write(contentsOf: Data([0x03]))
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.onOutput?("终端中断失败：\(error.localizedDescription)\n")
                }
            }
        }
    }

    func stop() {
        output?.readabilityHandler = nil
        if let process, process.isRunning { process.terminate() }
        try? input?.close()
        try? output?.close()
        process = nil
        input = nil
        output = nil
    }

    private static func cleanTerminalOutput(_ text: String) -> String {
        var result = text
        while let regex = try? NSRegularExpression(pattern: ".\u{0008}"),
              regex.firstMatch(in: result, range: NSRange(result.startIndex..<result.endIndex, in: result)) != nil {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        for pattern in [
            "\u{001B}\\][^\u{0007}]*(?:\u{0007}|\u{001B}\\\\)",
            "\u{001B}\\[[0-?]*[ -/]*[@-~]",
            "[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1A\\x1C-\\x1F\\x7F]"
        ] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
        let terminated = result.hasSuffix("\n")
        return lines.enumerated().map { index, line in
            // A partial line (the prompt, for example) keeps its trailing
            // whitespace so the next echoed input stays separated from it.
            if !terminated && index == lines.count - 1 {
                return String(line)
            }
            return line.replacingOccurrences(
                of: #"\s+$"#,
                with: "",
                options: .regularExpression
            )
        }
        .joined(separator: "\n")
    }
}
