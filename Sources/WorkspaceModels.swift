import Foundation

struct WorkspaceRecord: Codable, Hashable, Identifiable {
    let id: UUID
    var title: String
    var path: String
    var addedAt: Date
    var lastOpenedAt: Date

    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
}

enum TaskStatus: String, Codable, CaseIterable {
    case active
    case archived
}

struct TaskRecord: Codable, Hashable, Identifiable {
    let id: UUID
    let workspaceID: UUID
    var title: String
    var branch: String
    var worktreePath: String
    var status: TaskStatus
    var createdAt: Date
    var lastOpenedAt: Date

    var url: URL { URL(fileURLWithPath: worktreePath, isDirectory: true) }
}

struct PersistedWorkspaceState: Codable {
    var workspaces: [WorkspaceRecord] = []
    var tasks: [TaskRecord] = []
    var selectedWorkspaceID: UUID?
    var selectedTaskID: UUID?
    var inspectorVisible = false
    var navigatorVisible = false

    private enum CodingKeys: String, CodingKey {
        case workspaces, tasks, selectedWorkspaceID, selectedTaskID
        case inspectorVisible, navigatorVisible
    }

    init() {}

    init(
        workspaces: [WorkspaceRecord],
        tasks: [TaskRecord],
        selectedWorkspaceID: UUID?,
        selectedTaskID: UUID?,
        inspectorVisible: Bool,
        navigatorVisible: Bool = false
    ) {
        self.workspaces = workspaces
        self.tasks = tasks
        self.selectedWorkspaceID = selectedWorkspaceID
        self.selectedTaskID = selectedTaskID
        self.inspectorVisible = inspectorVisible
        self.navigatorVisible = navigatorVisible
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        workspaces = try values.decodeIfPresent([WorkspaceRecord].self, forKey: .workspaces) ?? []
        tasks = try values.decodeIfPresent([TaskRecord].self, forKey: .tasks) ?? []
        selectedWorkspaceID = try values.decodeIfPresent(UUID.self, forKey: .selectedWorkspaceID)
        selectedTaskID = try values.decodeIfPresent(UUID.self, forKey: .selectedTaskID)
        let isLegacyLayout = !values.contains(.navigatorVisible)
        inspectorVisible = isLegacyLayout
            ? false
            : (try values.decodeIfPresent(Bool.self, forKey: .inspectorVisible) ?? false)
        // Navigator did not exist in 1.x. Keeping it collapsed during migration
        // removes the duplicate native + DSH sidebars without losing workspaces.
        navigatorVisible = try values.decodeIfPresent(Bool.self, forKey: .navigatorVisible) ?? false
    }
}

enum WorkspaceValidationError: LocalizedError, Equatable {
    case missing
    case notDirectory
    case rootDirectory

    var errorDescription: String? {
        switch self {
        case .missing: return "所选工作区不存在。"
        case .notDirectory: return "请选择一个文件夹作为工作区。"
        case .rootDirectory: return "不能把文件系统根目录作为工作区。"
        }
    }
}

enum WorkspacePolicy {
    static func validate(_ url: URL) throws -> URL {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory) else {
            throw WorkspaceValidationError.missing
        }
        guard isDirectory.boolValue else { throw WorkspaceValidationError.notDirectory }
        guard resolved.path != "/" else { throw WorkspaceValidationError.rootDirectory }
        return resolved
    }

    static func contains(_ candidate: URL, inside root: URL) -> Bool {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let candidatePath = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }
}
