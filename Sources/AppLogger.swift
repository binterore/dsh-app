import Foundation

extension Notification.Name {
    static let appLogDidChange = Notification.Name("DeepSeekDesktop.appLogDidChange")
}

final class AppLogger {
    static let shared = AppLogger()

    private let queue = DispatchQueue(label: "com.deepseek.desktop.logger")
    private let formatter = ISO8601DateFormatter()
    private let maxBytes: UInt64 = 4 * 1024 * 1024

    private init() {
        try? AppPaths.ensureDirectories()
    }

    func log(_ message: String, category: String = "app") {
        queue.async {
            self.rotateIfNeeded()
            let sanitized = self.redact(message)
            let line = "\(self.formatter.string(from: Date())) [\(category)] \(sanitized)\n"
            guard let data = line.data(using: .utf8) else { return }
            let url = AppPaths.logFile
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } catch { }
            } else {
                try? data.write(to: url, options: .atomic)
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .appLogDidChange, object: nil)
            }
        }
    }

    func recentText(limit: Int = 80_000) -> String {
        queue.sync {
            guard let data = try? Data(contentsOf: AppPaths.logFile) else { return "" }
            let suffix = data.suffix(limit)
            return String(data: suffix, encoding: .utf8) ?? ""
        }
    }

    func makeDiagnosticsArchive(workspace: URL?, completion: @escaping (Result<URL, Error>) -> Void) {
        queue.async {
            do {
                try AppPaths.ensureDirectories()
                let temporary = FileManager.default.temporaryDirectory
                    .appendingPathComponent("DeepSeek-Diagnostics-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: AppPaths.logFile.path) {
                    try FileManager.default.copyItem(
                        at: AppPaths.logFile,
                        to: temporary.appendingPathComponent("desktop.log")
                    )
                }
                let metadata: [String: Any] = [
                    "generatedAt": self.formatter.string(from: Date()),
                    "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
                    "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development",
                    "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
                    "workspace": workspace?.path ?? NSNull()
                ]
                let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
                try metadataData.write(to: temporary.appendingPathComponent("metadata.json"), options: .atomic)

                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("DeepSeek-Diagnostics-\(Int(Date().timeIntervalSince1970)).zip")
                let result = CommandRunner.runSync(
                    executable: URL(fileURLWithPath: "/usr/bin/ditto"),
                    arguments: ["-c", "-k", "--sequesterRsrc", temporary.path, destination.path],
                    workingDirectory: temporary.deletingLastPathComponent()
                )
                try? FileManager.default.removeItem(at: temporary)
                guard result.status == 0 else {
                    throw CommandError.failed(command: "ditto", status: result.status, stderr: result.stderr)
                }
                DispatchQueue.main.async { completion(.success(destination)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func rotateIfNeeded() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: AppPaths.logFile.path),
              let size = attributes[.size] as? NSNumber,
              size.uint64Value > maxBytes else { return }
        let old = AppPaths.logsDirectory.appendingPathComponent("desktop.previous.log")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: AppPaths.logFile, to: old)
    }

    private func redact(_ message: String) -> String {
        var output = message
        let patterns = [
            #"(?i)(api[_-]?key|token|authorization|password)\s*[:=]\s*[^\s,;]+"#,
            #"(?i)bearer\s+[A-Za-z0-9._~+/-]+"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = regex.stringByReplacingMatches(in: output, range: range, withTemplate: "$1=<redacted>")
        }
        return output
    }
}
