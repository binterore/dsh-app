import Foundation

@main
enum TestMain {
    static func main() throws {
        try testRejectsRoot()
        testContainmentUsesPathBoundaries()
        try testWorkspaceStateRoundTrips()
        print("All DeepSeek Desktop core tests passed.")
    }

    private static func testRejectsRoot() throws {
        do {
            _ = try WorkspacePolicy.validate(URL(fileURLWithPath: "/"))
            throw TestFailure("文件系统根目录没有被拒绝")
        } catch WorkspaceValidationError.rootDirectory {
            // Expected.
        }
    }

    private static func testContainmentUsesPathBoundaries() {
        let root = URL(fileURLWithPath: "/tmp/project")
        precondition(WorkspacePolicy.contains(URL(fileURLWithPath: "/tmp/project/file.swift"), inside: root))
        precondition(!WorkspacePolicy.contains(URL(fileURLWithPath: "/tmp/project-other/file.swift"), inside: root))
    }

    private static func testWorkspaceStateRoundTrips() throws {
        let workspace = WorkspaceRecord(
            id: UUID(),
            title: "repo",
            path: "/tmp/repo",
            addedAt: Date(timeIntervalSince1970: 1),
            lastOpenedAt: Date(timeIntervalSince1970: 2)
        )
        let state = PersistedWorkspaceState(
            workspaces: [workspace],
            tasks: [],
            selectedWorkspaceID: workspace.id,
            selectedTaskID: nil,
            inspectorVisible: true
        )
        let decoded = try JSONDecoder().decode(
            PersistedWorkspaceState.self,
            from: JSONEncoder().encode(state)
        )
        guard decoded.workspaces.first?.path == "/tmp/repo",
              decoded.selectedWorkspaceID == workspace.id else {
            throw TestFailure("工作区状态编解码不一致")
        }
    }
}

private struct TestFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
