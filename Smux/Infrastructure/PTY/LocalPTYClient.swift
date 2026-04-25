import Darwin
import Foundation

nonisolated struct LocalPTYClientFactory: PTYClientFactory {
    func makeClient() -> any PTYClient {
        LocalPTYClient()
    }
}

nonisolated enum LocalPTYClientError: LocalizedError {
    case openFailed(errno: Int32)
    case missingMaster
    case writeFailed(errno: Int32)
    case resizeFailed(errno: Int32)

    var errorDescription: String? {
        switch self {
        case let .openFailed(errno):
            return "Failed to open PTY: \(String(cString: strerror(errno)))."
        case .missingMaster:
            return "PTY master is not available."
        case let .writeFailed(errno):
            return "Failed to write to PTY: \(String(cString: strerror(errno)))."
        case let .resizeFailed(errno):
            return "Failed to resize PTY: \(String(cString: strerror(errno)))."
        }
    }
}

nonisolated final class LocalPTYClient: PTYClient, @unchecked Sendable {
    typealias WriteFunction = (Int32, UnsafeRawPointer?, Int) -> Int

    var outputHandler: (@Sendable (Data) -> Void)?
    var terminationHandler: (@Sendable (Int32) -> Void)?

    private let lock = NSLock()
    private let writeFunction: WriteFunction
    private var process: Process?
    private var masterFileHandle: FileHandle?
    private var masterFileDescriptor: Int32?

    init(
        masterFileDescriptor: Int32? = nil,
        writeFunction: @escaping WriteFunction = Darwin.write
    ) {
        self.masterFileDescriptor = masterFileDescriptor
        self.writeFunction = writeFunction
    }

    var processID: Int32? {
        locked {
            process?.processIdentifier
        }
    }

    func start(_ request: PTYLaunchRequest) throws -> PTYLaunchResult {
        var master: Int32 = -1
        var slave: Int32 = -1
        var windowSize = winsize(
            ws_row: UInt16(max(1, request.rows)),
            ws_col: UInt16(max(1, request.columns)),
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        guard openpty(&master, &slave, nil, nil, &windowSize) == 0 else {
            throw LocalPTYClientError.openFailed(errno: errno)
        }

        do {
            let masterDescriptor = master
            let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: true)
            master = -1
            let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
            slave = -1
            let launchedProcess = Process()
            launchedProcess.executableURL = request.executableURL
            launchedProcess.arguments = request.arguments
            launchedProcess.currentDirectoryURL = request.workingDirectory
            launchedProcess.environment = request.environment
            launchedProcess.standardInput = slaveHandle
            launchedProcess.standardOutput = slaveHandle
            launchedProcess.standardError = slaveHandle

            masterHandle.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }

                self?.outputHandler?(data)
            }

            launchedProcess.terminationHandler = { [weak self] process in
                self?.closeMaster()
                self?.terminationHandler?(process.terminationStatus)
            }

            try launchedProcess.run()
            slaveHandle.closeFile()

            locked {
                process = launchedProcess
                masterFileHandle = masterHandle
                masterFileDescriptor = masterDescriptor
            }

            return PTYLaunchResult(processID: launchedProcess.processIdentifier)
        } catch {
            if master >= 0 {
                close(master)
            }
            if slave >= 0 {
                close(slave)
            }
            throw error
        }
    }

    func write(_ data: Data) throws {
        guard let descriptor = locked({ masterFileDescriptor }) else {
            throw LocalPTYClientError.missingMaster
        }

        guard !data.isEmpty else {
            return
        }

        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return
            }

            var writtenCount = 0
            while writtenCount < buffer.count {
                let result = writeFunction(
                    descriptor,
                    baseAddress.advanced(by: writtenCount),
                    buffer.count - writtenCount
                )

                if result > 0 {
                    writtenCount += result
                    continue
                }

                let writeErrno = errno
                if result < 0, writeErrno == EINTR {
                    continue
                }

                throw LocalPTYClientError.writeFailed(errno: writeErrno)
            }
        }
    }

    func resize(columns: Int, rows: Int) throws {
        guard let descriptor = locked({ masterFileDescriptor }) else {
            throw LocalPTYClientError.missingMaster
        }

        var windowSize = winsize(
            ws_row: UInt16(max(1, rows)),
            ws_col: UInt16(max(1, columns)),
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        guard ioctl(descriptor, TIOCSWINSZ, &windowSize) == 0 else {
            throw LocalPTYClientError.resizeFailed(errno: errno)
        }
    }

    func terminate() {
        let runningProcess = locked {
            process
        }

        runningProcess?.terminate()
    }

    private func closeMaster() {
        let handle = locked {
            let handle = masterFileHandle
            masterFileHandle = nil
            masterFileDescriptor = nil
            return handle
        }

        handle?.readabilityHandler = nil
        handle?.closeFile()
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
