import Foundation

nonisolated enum GitBranchLookupResult: Equatable, Sendable {
    case branch(String)
    case noBranch
    case lookupFailed
}

nonisolated protocol GitBranchProviding: Sendable {
    func currentBranch(for rootURL: URL) async -> GitBranchLookupResult
}

nonisolated struct NoopGitBranchProvider: GitBranchProviding {
    func currentBranch(for rootURL: URL) async -> GitBranchLookupResult {
        .noBranch
    }
}

nonisolated struct ProcessGitBranchProvider: GitBranchProviding {
    private let processRunner: any GitProcessRunning

    init(processRunner: any GitProcessRunning = ProcessGitRunner()) {
        self.processRunner = processRunner
    }

    func currentBranch(for rootURL: URL) async -> GitBranchLookupResult {
        do {
            let result = try await processRunner.runGit(
                arguments: ["symbolic-ref", "--quiet", "--short", "HEAD"],
                workingDirectory: rootURL
            )

            guard result.terminationStatus == 0 else {
                return .noBranch
            }

            let branch = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !branch.isEmpty else {
                return .noBranch
            }

            return .branch(branch)
        } catch {
            return .lookupFailed
        }
    }
}
