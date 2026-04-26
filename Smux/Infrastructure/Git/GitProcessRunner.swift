import Foundation

nonisolated struct GitCommandResult: Equatable, Sendable {
    var terminationStatus: Int32
    var standardOutput: String
    var standardError: String
}

nonisolated protocol GitProcessRunning: Sendable {
    func runGit(arguments: [String], workingDirectory: URL) async throws -> GitCommandResult
}

nonisolated struct ProcessGitRunner: GitProcessRunning {
    private let executableURL: URL

    init(executableURL: URL = URL(fileURLWithPath: "/usr/bin/git")) {
        self.executableURL = executableURL
    }

    func runGit(arguments: [String], workingDirectory: URL) async throws -> GitCommandResult {
        try await Task.detached(priority: .utility) { [executableURL] in
            try Task.checkCancellation()

            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            return GitCommandResult(
                terminationStatus: process.terminationStatus,
                standardOutput: String(data: outputData, encoding: .utf8) ?? "",
                standardError: String(data: errorData, encoding: .utf8) ?? ""
            )
        }.value
    }
}
