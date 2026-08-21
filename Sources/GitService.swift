import Foundation

struct GitChange: Hashable, Identifiable {
    let path: String
    let indexStatus: Character
    let worktreeStatus: Character

    var id: String { path }
    var isStaged: Bool { indexStatus != " " && indexStatus != "?" }
    var isUntracked: Bool { indexStatus == "?" && worktreeStatus == "?" }

    var displayStatus: String {
        if isUntracked { return "U" }
        let value = isStaged ? indexStatus : worktreeStatus
        return String(value)
    }
}

struct GitSnapshot {
    let root: URL
    let branch: String
    let changes: [GitChange]
    let ahead: Int
    let behind: Int
    let additions: Int
    let deletions: Int
}

final class GitService {
    private let gitURL = URL(fileURLWithPath: "/usr/bin/git")

    func snapshot(at directory: URL, completion: @escaping (Result<GitSnapshot, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let rootResult = CommandRunner.runSync(
                executable: self.gitURL,
                arguments: ["rev-parse", "--show-toplevel"],
                workingDirectory: directory
            )
            guard rootResult.status == 0 else {
                DispatchQueue.main.async {
                    completion(.failure(CommandError.failed(
                        command: "git rev-parse",
                        status: rootResult.status,
                        stderr: rootResult.stderr
                    )))
                }
                return
            }
            let root = URL(fileURLWithPath: rootResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            let status = CommandRunner.runSync(
                executable: self.gitURL,
                arguments: ["-c", "core.quotepath=false", "status", "--porcelain=v1", "--branch", "--untracked-files=all"],
                workingDirectory: root
            )
            guard status.status == 0 else {
                DispatchQueue.main.async {
                    completion(.failure(CommandError.failed(command: "git status", status: status.status, stderr: status.stderr)))
                }
                return
            }
            let snapshot = self.parseStatus(status.stdout, root: root)
            DispatchQueue.main.async { completion(.success(snapshot)) }
        }
    }

    func diff(for change: GitChange, at root: URL, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let arguments: [String]
            if change.isUntracked {
                arguments = ["diff", "--no-index", "--", "/dev/null", change.path]
            } else if change.isStaged && change.worktreeStatus == " " {
                arguments = ["diff", "--cached", "--no-ext-diff", "--", change.path]
            } else {
                arguments = ["diff", "--no-ext-diff", "--", change.path]
            }
            let result = CommandRunner.runSync(executable: self.gitURL, arguments: arguments, workingDirectory: root)
            // git diff --no-index returns 1 when files differ; that is success for this view.
            if result.status == 0 || (change.isUntracked && result.status == 1) {
                DispatchQueue.main.async { completion(.success(result.stdout)) }
            } else {
                DispatchQueue.main.async {
                    completion(.failure(CommandError.failed(command: "git diff", status: result.status, stderr: result.stderr)))
                }
            }
        }
    }

    func stage(_ paths: [String], at root: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        mutate(arguments: ["add", "--"] + paths, at: root, completion: completion)
    }

    func unstage(_ paths: [String], at root: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        mutate(arguments: ["restore", "--staged", "--"] + paths, at: root, completion: completion)
    }

    func discard(_ changes: [GitChange], at root: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            for change in changes {
                let result: CommandResult
                if change.isUntracked {
                    let target = root.appendingPathComponent(change.path).standardizedFileURL
                    guard WorkspacePolicy.contains(target, inside: root) else {
                        DispatchQueue.main.async {
                            completion(.failure(CommandError.couldNotLaunch("拒绝删除工作区之外的文件。")))
                        }
                        return
                    }
                    do {
                        try FileManager.default.removeItem(at: target)
                        continue
                    } catch {
                        DispatchQueue.main.async { completion(.failure(error)) }
                        return
                    }
                } else {
                    result = CommandRunner.runSync(
                        executable: self.gitURL,
                        arguments: ["restore", "--staged", "--worktree", "--", change.path],
                        workingDirectory: root
                    )
                }
                guard result.status == 0 else {
                    DispatchQueue.main.async {
                        completion(.failure(CommandError.failed(command: "git restore", status: result.status, stderr: result.stderr)))
                    }
                    return
                }
            }
            DispatchQueue.main.async { completion(.success(())) }
        }
    }

    func commit(message: String, at root: URL, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = CommandRunner.runSync(
                executable: self.gitURL,
                arguments: ["commit", "-m", message],
                workingDirectory: root
            )
            if result.status == 0 {
                DispatchQueue.main.async { completion(.success(result.stdout)) }
            } else {
                DispatchQueue.main.async {
                    completion(.failure(CommandError.failed(command: "git commit", status: result.status, stderr: result.stderr)))
                }
            }
        }
    }

    func createWorktree(
        workspace: WorkspaceRecord,
        title: String,
        requestedBranch: String?,
        completion: @escaping (Result<TaskRecord, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let rootResult = CommandRunner.runSync(
                executable: self.gitURL,
                arguments: ["rev-parse", "--show-toplevel"],
                workingDirectory: workspace.url
            )
            guard rootResult.status == 0 else {
                DispatchQueue.main.async {
                    completion(.failure(CommandError.failed(
                        command: "git rev-parse",
                        status: rootResult.status,
                        stderr: "创建隔离任务需要 Git 仓库。\n" + rootResult.stderr
                    )))
                }
                return
            }
            let repositoryRoot = URL(fileURLWithPath: rootResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            let slug = Self.slug(requestedBranch?.isEmpty == false ? requestedBranch! : title)
            let branch = slug.hasPrefix("codex/") ? slug : "codex/\(slug)"
            let destination = AppPaths.worktreesDirectory
                .appendingPathComponent(Self.repositoryKey(repositoryRoot), isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            let branchProbe = CommandRunner.runSync(
                executable: self.gitURL,
                arguments: ["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"],
                workingDirectory: repositoryRoot
            )
            let arguments: [String]
            if branchProbe.status == 0 {
                arguments = ["worktree", "add", destination.path, branch]
            } else {
                arguments = ["worktree", "add", "-b", branch, destination.path, "HEAD"]
            }
            let result = CommandRunner.runSync(executable: self.gitURL, arguments: arguments, workingDirectory: repositoryRoot)
            guard result.status == 0 else {
                DispatchQueue.main.async {
                    completion(.failure(CommandError.failed(command: "git worktree add", status: result.status, stderr: result.stderr)))
                }
                return
            }
            let task = TaskRecord(
                id: UUID(),
                workspaceID: workspace.id,
                title: title,
                branch: branch,
                worktreePath: destination.path,
                status: .active,
                createdAt: Date(),
                lastOpenedAt: Date()
            )
            DispatchQueue.main.async { completion(.success(task)) }
        }
    }

    func removeWorktree(_ task: TaskRecord, workspace: WorkspaceRecord, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = CommandRunner.runSync(
                executable: self.gitURL,
                arguments: ["worktree", "remove", task.worktreePath],
                workingDirectory: workspace.url
            )
            if result.status == 0 {
                DispatchQueue.main.async { completion(.success(())) }
            } else {
                DispatchQueue.main.async {
                    completion(.failure(CommandError.failed(command: "git worktree remove", status: result.status, stderr: result.stderr)))
                }
            }
        }
    }

    private func mutate(arguments: [String], at root: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = CommandRunner.runSync(executable: self.gitURL, arguments: arguments, workingDirectory: root)
            DispatchQueue.main.async {
                if result.status == 0 {
                    completion(.success(()))
                } else {
                    completion(.failure(CommandError.failed(command: "git \(arguments.first ?? "")", status: result.status, stderr: result.stderr)))
                }
            }
        }
    }

    private func parseStatus(_ output: String, root: URL) -> GitSnapshot {
        var branch = "detached"
        var ahead = 0
        var behind = 0
        var changes: [GitChange] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            if line.hasPrefix("## ") {
                let header = String(line.dropFirst(3))
                branch = header.components(separatedBy: "...").first ?? header
                if let range = header.range(of: #"ahead (\d+)"#, options: .regularExpression) {
                    ahead = Int(header[range].split(separator: " ").last ?? "0") ?? 0
                }
                if let range = header.range(of: #"behind (\d+)"#, options: .regularExpression) {
                    behind = Int(header[range].split(separator: " ").last ?? "0") ?? 0
                }
                continue
            }
            guard line.count >= 4 else { continue }
            let index = line[line.startIndex]
            let worktreeIndex = line.index(after: line.startIndex)
            let worktree = line[worktreeIndex]
            var path = String(line.dropFirst(3))
            if let arrow = path.range(of: " -> ") { path = String(path[arrow.upperBound...]) }
            changes.append(GitChange(path: path, indexStatus: index, worktreeStatus: worktree))
        }
        let stats = lineStats(at: root, changes: changes)
        return GitSnapshot(
            root: root,
            branch: branch,
            changes: changes,
            ahead: ahead,
            behind: behind,
            additions: stats.additions,
            deletions: stats.deletions
        )
    }

    private func lineStats(at root: URL, changes: [GitChange]) -> (additions: Int, deletions: Int) {
        let result = CommandRunner.runSync(
            executable: gitURL,
            arguments: ["diff", "--numstat", "HEAD", "--"],
            workingDirectory: root
        )
        var additions = 0
        var deletions = 0
        if result.status == 0 {
            for line in result.stdout.split(separator: "\n") {
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard fields.count >= 2 else { continue }
                additions += Int(fields[0]) ?? 0
                deletions += Int(fields[1]) ?? 0
            }
        }

        // `git diff` excludes untracked files. Count small UTF-8 files so the
        // environment card matches the review total a user actually sees.
        for change in changes where change.isUntracked {
            let file = root.appendingPathComponent(change.path).standardizedFileURL
            guard WorkspacePolicy.contains(file, inside: root),
                  let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize,
                  size <= 5_000_000,
                  let data = try? Data(contentsOf: file),
                  let text = String(data: data, encoding: .utf8) else { continue }
            let breaks = text.reduce(into: 0) { count, character in
                if character == "\n" { count += 1 }
            }
            additions += breaks + (!text.isEmpty && !text.hasSuffix("\n") ? 1 : 0)
        }
        return (additions, deletions)
    }

    private static func slug(_ value: String) -> String {
        let lowered = value.lowercased()
        let allowed = lowered.map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" || character == "/" { return character }
            return "-"
        }
        let collapsed = String(allowed)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-/"))
        return collapsed.isEmpty ? "task-\(Int(Date().timeIntervalSince1970))" : collapsed
    }

    private static func repositoryKey(_ root: URL) -> String {
        let bytes = Array(root.path.utf8)
        var hash: UInt64 = 1469598103934665603
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16)
    }
}
