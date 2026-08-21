import Foundation

struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum CommandError: LocalizedError {
    case failed(command: String, status: Int32, stderr: String)
    case couldNotLaunch(String)

    var errorDescription: String? {
        switch self {
        case let .failed(command, status, stderr):
            return "\(command) 退出码 \(status)：\(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        case let .couldNotLaunch(message):
            return message
        }
    }
}

enum CommandRunner {
    @discardableResult
    static func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String]? = nil,
        completion: @escaping (CommandResult) -> Void
    ) -> Process? {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = environment ?? ProcessInfo.processInfo.environment
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.terminationHandler = { process in
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let result = CommandResult(
                status: process.terminationStatus,
                stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                stderr: String(data: stderrData, encoding: .utf8) ?? ""
            )
            DispatchQueue.main.async { completion(result) }
        }
        do {
            try process.run()
            return process
        } catch {
            DispatchQueue.main.async {
                completion(CommandResult(status: -1, stdout: "", stderr: error.localizedDescription))
            }
            return nil
        }
    }

    static func runSync(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String]? = nil
    ) -> CommandResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = environment ?? ProcessInfo.processInfo.environment
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
            process.waitUntilExit()
            return CommandResult(
                status: process.terminationStatus,
                stdout: String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                stderr: String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            )
        } catch {
            return CommandResult(status: -1, stdout: "", stderr: error.localizedDescription)
        }
    }
}
