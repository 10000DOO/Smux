import Foundation

nonisolated struct PTYLaunchRequest: Equatable, Sendable {
    var executableURL: URL
    var arguments: [String]
    var workingDirectory: URL
    var environment: [String: String]?
    var columns: Int
    var rows: Int
}

nonisolated struct PTYLaunchResult: Equatable, Sendable {
    var processID: Int32
}

nonisolated protocol PTYClient: AnyObject {
    var outputHandler: (@Sendable (Data) -> Void)? { get set }
    var terminationHandler: (@Sendable (Int32) -> Void)? { get set }
    var processID: Int32? { get }

    func start(_ request: PTYLaunchRequest) throws -> PTYLaunchResult
    func write(_ data: Data) throws
    func resize(columns: Int, rows: Int) throws
    func terminate()
}

nonisolated protocol PTYClientFactory: Sendable {
    func makeClient() -> any PTYClient
}
