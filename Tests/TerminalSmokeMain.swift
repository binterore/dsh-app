import Foundation

@main
struct TerminalSmokeMain {
    static func main() {
        let session = TerminalSession()
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        var transcript = ""
        session.onOutput = { transcript += $0 }
        session.start(in: directory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            session.send("printf '__TERMINAL_OK__\\n'")
        }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !transcript.contains("__TERMINAL_OK__") {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        session.stop()

        guard transcript.contains("__TERMINAL_OK__") else {
            FileHandle.standardError.write(Data("Terminal smoke test failed. Transcript:\n\(transcript)\n".utf8))
            Foundation.exit(1)
        }
        print("Terminal PTY smoke test passed.")
    }
}
