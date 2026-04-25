import Darwin
import Foundation

nonisolated enum LocalFileWatcherError: LocalizedError {
    case openFailed(URL, errno: Int32)

    var errorDescription: String? {
        switch self {
        case .openFailed(let url, let errno):
            return "Failed to watch \(url.path): \(String(cString: strerror(errno)))."
        }
    }
}

nonisolated final class LocalFileWatcher: FileWatching, @unchecked Sendable {
    private struct Observation {
        var source: DispatchSourceFileSystemObject
    }

    private let lock = NSLock()
    private let sourceQueue: DispatchQueue
    private let debouncer: FileWatchDebouncer
    private var observations: [FileWatchScope: Observation] = [:]
    private var lockedEventHandler: (@Sendable ([FileWatchEvent]) -> Void)?

    var eventHandler: (@Sendable ([FileWatchEvent]) -> Void)? {
        get {
            locked {
                lockedEventHandler
            }
        }
        set {
            locked {
                lockedEventHandler = newValue
            }
        }
    }

    init(
        debounceInterval: TimeInterval = 0.25,
        sourceQueue: DispatchQueue = DispatchQueue(label: "Smux.LocalFileWatcher.Source"),
        deliveryQueue: DispatchQueue = DispatchQueue(label: "Smux.LocalFileWatcher.Delivery")
    ) {
        self.sourceQueue = sourceQueue
        self.debouncer = FileWatchDebouncer(interval: debounceInterval, queue: deliveryQueue)
        self.debouncer.eventHandler = { [weak self] events in
            self?.deliver(events)
        }
    }

    deinit {
        stopAll()
        debouncer.cancel()
    }

    func startWatching(_ scope: FileWatchScope) throws {
        guard locked({ observations[scope] == nil }) else {
            return
        }

        let descriptor = open(scope.url.path, O_EVTONLY)

        guard descriptor >= 0 else {
            throw LocalFileWatcherError.openFailed(scope.url, errno: errno)
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: Self.makeEventMask(),
            queue: sourceQueue
        )

        source.setEventHandler { [weak self, source] in
            let event = FileWatchEvent(
                scope: scope,
                kind: Self.eventKind(for: source.data, scope: scope)
            )
            self?.debouncer.submit(event)
        }

        source.setCancelHandler {
            close(descriptor)
        }

        let shouldCancel = locked {
            guard observations[scope] == nil else {
                return true
            }

            observations[scope] = Observation(source: source)
            return false
        }

        if shouldCancel {
            source.cancel()
            return
        }

        source.resume()
    }

    func stopWatching(_ scope: FileWatchScope) {
        let observation = locked {
            observations.removeValue(forKey: scope)
        }

        debouncer.cancel(scope: scope)
        observation?.source.cancel()
    }

    func stopAll() {
        let activeObservations = locked {
            let activeObservations = Array(observations.values)
            observations.removeAll()
            return activeObservations
        }

        activeObservations.forEach { observation in
            observation.source.cancel()
        }
        debouncer.cancel()
    }

    private func deliver(_ events: [FileWatchEvent]) {
        let delivery = locked {
            (
                events.filter { observations[$0.scope] != nil },
                lockedEventHandler
            )
        }

        guard !delivery.0.isEmpty else {
            return
        }

        delivery.1?(delivery.0)
    }

    private static func makeEventMask() -> DispatchSource.FileSystemEvent {
        [
            .attrib,
            .delete,
            .extend,
            .link,
            .rename,
            .revoke,
            .write,
        ]
    }

    private static func eventKind(
        for flags: DispatchSource.FileSystemEvent,
        scope: FileWatchScope
    ) -> FileWatchEventKind {
        if flags.contains(.delete) || flags.contains(.revoke) {
            return .deleted
        }

        if flags.contains(.rename) {
            return .renamed
        }

        if flags.contains(.attrib) || flags.contains(.link) {
            return .metadataChanged
        }

        switch scope {
        case .workspaceRoot:
            return .contentsChanged
        case .openFile:
            return .modified
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
