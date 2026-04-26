import XCTest
@testable import Smux

final class GitBranchProviderTests: XCTestCase {
    func testProcessGitBranchProviderReturnsBranchFromSuccessfulOutput() async {
        let rootURL = URL(fileURLWithPath: "/tmp/SmuxGitBranch")
        let runner = StubGitProcessRunner(
            result: .success(
                GitCommandResult(
                    terminationStatus: 0,
                    standardOutput: "feature/workspaces\n",
                    standardError: ""
                )
            )
        )
        let provider = ProcessGitBranchProvider(processRunner: runner)

        let result = await provider.currentBranch(for: rootURL)
        let request = await runner.firstRequest()

        XCTAssertEqual(result, .branch("feature/workspaces"))
        XCTAssertEqual(request?.arguments, ["symbolic-ref", "--quiet", "--short", "HEAD"])
        XCTAssertEqual(request?.workingDirectory, rootURL)
    }

    func testProcessGitBranchProviderReturnsNoBranchWhenGitCommandHasNoBranch() async {
        let runner = StubGitProcessRunner(
            result: .success(
                GitCommandResult(
                    terminationStatus: 1,
                    standardOutput: "",
                    standardError: "fatal: not a git repository"
                )
            )
        )
        let provider = ProcessGitBranchProvider(processRunner: runner)

        let result = await provider.currentBranch(for: URL(fileURLWithPath: "/tmp/SmuxNoGitBranch"))

        XCTAssertEqual(result, .noBranch)
    }

    func testProcessGitBranchProviderReturnsLookupFailedWhenRunnerThrows() async {
        let runner = StubGitProcessRunner(result: .failure)
        let provider = ProcessGitBranchProvider(processRunner: runner)

        let result = await provider.currentBranch(for: URL(fileURLWithPath: "/tmp/SmuxGitFailure"))

        XCTAssertEqual(result, .lookupFailed)
    }
}

private actor StubGitProcessRunner: GitProcessRunning {
    private var requests: [GitProcessRequest] = []
    private let result: StubResult

    init(result: StubResult) {
        self.result = result
    }

    func runGit(arguments: [String], workingDirectory: URL) async throws -> GitCommandResult {
        requests.append(GitProcessRequest(arguments: arguments, workingDirectory: workingDirectory))

        switch result {
        case let .success(commandResult):
            return commandResult
        case .failure:
            throw GitBranchProviderTestError.failed
        }
    }

    func firstRequest() -> GitProcessRequest? {
        requests.first
    }
}

private struct GitProcessRequest: Equatable, Sendable {
    var arguments: [String]
    var workingDirectory: URL
}

private enum StubResult: Sendable {
    case success(GitCommandResult)
    case failure
}

private enum GitBranchProviderTestError: Error {
    case failed
}
