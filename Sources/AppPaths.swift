import Foundation

enum AppPaths {
    static let fileManager = FileManager.default

    static var applicationSupport: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("DeepSeekDesktop", isDirectory: true)
    }

    static var stateFile: URL {
        applicationSupport.appendingPathComponent("workspace-state.json")
    }

    static var logsDirectory: URL {
        applicationSupport.appendingPathComponent("Logs", isDirectory: true)
    }

    static var logFile: URL {
        logsDirectory.appendingPathComponent("desktop.log")
    }

    static var worktreesDirectory: URL {
        applicationSupport.appendingPathComponent("Worktrees", isDirectory: true)
    }

    static var runtimeDirectory: URL {
        applicationSupport.appendingPathComponent("Runtime", isDirectory: true)
    }

    static func ensureDirectories() throws {
        for directory in [applicationSupport, logsDirectory, worktreesDirectory, runtimeDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
