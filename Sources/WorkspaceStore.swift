import Foundation

extension Notification.Name {
    static let workspaceStoreDidChange = Notification.Name("DeepSeekDesktop.workspaceStoreDidChange")
}

final class WorkspaceStore {
    private(set) var state: PersistedWorkspaceState

    init() {
        try? AppPaths.ensureDirectories()
        if let data = try? Data(contentsOf: AppPaths.stateFile),
           let decoded = try? JSONDecoder.deepSeek.decode(PersistedWorkspaceState.self, from: data) {
            state = decoded
        } else {
            state = PersistedWorkspaceState()
        }
        pruneMissingRecords()
    }

    var selectedWorkspace: WorkspaceRecord? {
        guard let id = state.selectedWorkspaceID else { return nil }
        return state.workspaces.first { $0.id == id }
    }

    var selectedTask: TaskRecord? {
        guard let id = state.selectedTaskID else { return nil }
        return state.tasks.first { $0.id == id && $0.status == .active }
    }

    var activeRoot: URL? {
        selectedTask?.url ?? selectedWorkspace?.url
    }

    @discardableResult
    func addWorkspace(_ url: URL) throws -> WorkspaceRecord {
        let validated = try WorkspacePolicy.validate(url)
        if let index = state.workspaces.firstIndex(where: { $0.url.resolvingSymlinksInPath() == validated }) {
            state.workspaces[index].lastOpenedAt = Date()
            selectWorkspace(state.workspaces[index].id)
            return state.workspaces[index]
        }
        let record = WorkspaceRecord(
            id: UUID(),
            title: validated.lastPathComponent,
            path: validated.path,
            addedAt: Date(),
            lastOpenedAt: Date()
        )
        state.workspaces.append(record)
        state.selectedWorkspaceID = record.id
        state.selectedTaskID = nil
        saveAndNotify()
        return record
    }

    func selectWorkspace(_ id: UUID) {
        guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return }
        if state.selectedWorkspaceID == id && state.selectedTaskID == nil { return }
        state.workspaces[index].lastOpenedAt = Date()
        state.selectedWorkspaceID = id
        state.selectedTaskID = nil
        saveAndNotify()
    }

    func selectTask(_ id: UUID) {
        guard let index = state.tasks.firstIndex(where: { $0.id == id && $0.status == .active }) else { return }
        if state.selectedTaskID == id { return }
        state.tasks[index].lastOpenedAt = Date()
        state.selectedWorkspaceID = state.tasks[index].workspaceID
        state.selectedTaskID = id
        saveAndNotify()
    }

    func tasks(for workspaceID: UUID, includeArchived: Bool = false) -> [TaskRecord] {
        state.tasks
            .filter { $0.workspaceID == workspaceID && (includeArchived || $0.status == .active) }
            .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    func appendTask(_ task: TaskRecord) {
        state.tasks.append(task)
        state.selectedWorkspaceID = task.workspaceID
        state.selectedTaskID = task.id
        saveAndNotify()
    }

    func archiveTask(_ id: UUID) {
        guard let index = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[index].status = .archived
        if state.selectedTaskID == id { state.selectedTaskID = nil }
        saveAndNotify()
    }

    func setInspectorVisible(_ visible: Bool) {
        guard state.inspectorVisible != visible else { return }
        state.inspectorVisible = visible
        saveAndNotify()
    }

    func setNavigatorVisible(_ visible: Bool) {
        guard state.navigatorVisible != visible else { return }
        state.navigatorVisible = visible
        saveAndNotify()
    }

    private func pruneMissingRecords() {
        state.workspaces.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
        state.tasks.removeAll {
            $0.status == .active && !FileManager.default.fileExists(atPath: $0.worktreePath)
        }
        if !state.workspaces.contains(where: { $0.id == state.selectedWorkspaceID }) {
            state.selectedWorkspaceID = state.workspaces.sorted { $0.lastOpenedAt > $1.lastOpenedAt }.first?.id
            state.selectedTaskID = nil
        }
        if !state.tasks.contains(where: { $0.id == state.selectedTaskID && $0.status == .active }) {
            state.selectedTaskID = nil
        }
        save()
    }

    private func saveAndNotify() {
        save()
        NotificationCenter.default.post(name: .workspaceStoreDidChange, object: self)
    }

    private func save() {
        guard let data = try? JSONEncoder.deepSeek.encode(state) else { return }
        try? data.write(to: AppPaths.stateFile, options: .atomic)
    }
}

private extension JSONEncoder {
    static var deepSeek: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var deepSeek: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
